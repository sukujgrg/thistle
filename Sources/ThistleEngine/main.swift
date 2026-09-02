import Darwin
import Foundation

#if os(macOS) && arch(arm64)

  import ThistleSupport

  EngineLogFile.install()

  let engineRuntime = EngineRuntime()
  let engineDelegate = EngineListenerDelegate(runtime: engineRuntime)
  let engineListener = NSXPCListener(machServiceName: EngineIdentity.xpcService)
  engineListener.delegate = engineDelegate
  engineListener.resume()
  dispatchMain()

#else

  fputs("Thistle Engine requires macOS 26 on Apple silicon.\n", stderr)
  exit(1)

#endif
