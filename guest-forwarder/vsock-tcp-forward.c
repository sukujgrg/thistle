/*
 * Guest-side vsock → TCP forwarder for Thistle.
 * Listens on AF_VSOCK and splices each connection to 127.0.0.1:<tcp-port>.
 *
 * Build (linux/arm64, static):
 *   make guest-forwarder
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include <linux/vm_sockets.h>

struct splice_pair {
  int from_fd;
  int to_fd;
};

static void *splice_one_way(void *arg) {
  struct splice_pair *pair = arg;
  char buffer[64 * 1024];
  for (;;) {
    ssize_t n = read(pair->from_fd, buffer, sizeof(buffer));
    if (n == 0) {
      break;
    }
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    ssize_t off = 0;
    while (off < n) {
      ssize_t w = write(pair->to_fd, buffer + off, (size_t)(n - off));
      if (w < 0) {
        if (errno == EINTR) {
          continue;
        }
        goto done;
      }
      off += w;
    }
  }
done:
  shutdown(pair->to_fd, SHUT_WR);
  return NULL;
}

static int connect_tcp(uint16_t port) {
  int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return -1;
  }
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    int saved = errno;
    close(fd);
    errno = saved;
    return -1;
  }
  return fd;
}

static void handle_client(int client_fd, uint16_t tcp_port) {
  int tcp_fd = connect_tcp(tcp_port);
  if (tcp_fd < 0) {
    close(client_fd);
    return;
  }

  struct splice_pair a = {.from_fd = client_fd, .to_fd = tcp_fd};
  struct splice_pair b = {.from_fd = tcp_fd, .to_fd = client_fd};
  pthread_t t1;
  pthread_t t2;
  if (pthread_create(&t1, NULL, splice_one_way, &a) != 0) {
    close(client_fd);
    close(tcp_fd);
    return;
  }
  if (pthread_create(&t2, NULL, splice_one_way, &b) != 0) {
    shutdown(client_fd, SHUT_RDWR);
    shutdown(tcp_fd, SHUT_RDWR);
    pthread_join(t1, NULL);
    close(client_fd);
    close(tcp_fd);
    return;
  }
  pthread_join(t1, NULL);
  pthread_join(t2, NULL);
  close(client_fd);
  close(tcp_fd);
}

static void *client_thread(void *arg) {
  uintptr_t packed = (uintptr_t)arg;
  int client_fd = (int)(packed & 0xffffffffu);
  uint16_t tcp_port = (uint16_t)(packed >> 32);
  handle_client(client_fd, tcp_port);
  return NULL;
}

int main(int argc, char **argv) {
  uint32_t vsock_port = 18765;
  uint16_t tcp_port = 3000;
  if (argc >= 2) {
    vsock_port = (uint32_t)strtoul(argv[1], NULL, 10);
  }
  if (argc >= 3) {
    tcp_port = (uint16_t)strtoul(argv[2], NULL, 10);
  }

  signal(SIGPIPE, SIG_IGN);

  int listen_fd = socket(AF_VSOCK, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (listen_fd < 0) {
    perror("socket(AF_VSOCK)");
    return 1;
  }

  struct sockaddr_vm addr;
  memset(&addr, 0, sizeof(addr));
  addr.svm_family = AF_VSOCK;
  addr.svm_cid = VMADDR_CID_ANY;
  addr.svm_port = vsock_port;

  if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    perror("bind(AF_VSOCK)");
    close(listen_fd);
    return 1;
  }
  if (listen(listen_fd, 128) != 0) {
    perror("listen(AF_VSOCK)");
    close(listen_fd);
    return 1;
  }

  fprintf(stderr, "vsock-tcp-forward listening vsock:%u -> 127.0.0.1:%u\n", vsock_port,
          tcp_port);

  for (;;) {
    int client_fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC);
    if (client_fd < 0) {
      if (errno == EINTR) {
        continue;
      }
      perror("accept");
      break;
    }
    uintptr_t packed = ((uintptr_t)tcp_port << 32) | (uintptr_t)(uint32_t)client_fd;
    pthread_t thread;
    if (pthread_create(&thread, NULL, client_thread, (void *)packed) != 0) {
      close(client_fd);
      continue;
    }
    pthread_detach(thread);
  }

  close(listen_fd);
  return 1;
}
