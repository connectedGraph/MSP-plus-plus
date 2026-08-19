# MSP++ — 统一桥接(Unified Bridge)

MSP++ 是 Model Shell Protocol 的一个实验 fork,针对一个核心主张:

> **命令面不应该手写。** 用现成宽松开源运行时(toybox coreutils + CPython + git)通过统一 bridge broker 支撑命令面;路径映射 + 输出 sanitize(映射层)与文件访问拦截(解释器层)负责隔离。MSP 保留的是 shell 语义层(parser / registry / WorkspaceFS / policy / audit),不是命令实现。

## 为什么

- **手写 117 个 POSIX 命令 = 重复造轮子。** GNU coreutils 已有宽松重写:toybox(BSD-0,C)、uutils/coreutils(MIT,Rust)。打包一个 + 路径映射即可,不用 Swift 重写每个工具。
- **"重写解释器"只在重运行时不可行,而重运行时本就不该重写。** git/python 是几十万行状态机,重写不现实 → 借真运行时(libgit2 / CPython)。上游 MSP 自己也是借(libgit2 绑定、CPython 嵌入)。
- **两条隔离路的分界是"有没有可覆盖的文件访问 API":**
  - 编译二进制(git / coreutils / toybox):无语言级文件 API 钩子,文件访问焊死在 C 代码里 → 只能**映射**(真进程跑物理工作区 + path mapper + 输出 sanitize);
  - 解释器(Python / Node):`os` 模块 / `builtins.open` 是语言级可覆盖接口 → 能**拦截**(嵌进进程,open() 走虚拟 FS)。
  - 这是客观分界,不是实现选择。libgit2 虽可嵌入,但它内部直接调系统 open,没有"把读操作重定向到虚拟 FS"的口子。

## 架构

```
MSP++ (命令面 = 真实运行时)
├─ 语义层 (保留下游)        : shell parser / command registry / WorkspaceFS / policy / audit
└─ 统一 bridge (MSPBridge) : 一个 enable(.bridge) 注册三层
     ├─ coreutils → toybox 多调用二进制 + install_flat 符号链接,每个 applet 注册为外部命令  (映射层)
     ├─ git       → 真实 git 二进制                                                        (映射层)
     └─ python    → 嵌入式 CPython(MSPCPythonEngine dlopen libpython)+ VFS broker          (拦截层)
```

接线点:`Implementations/Swift/Sources/MSPBridge/MSPBridge.swift` 的 `MSPBridge.bridgeProfile(_:)`,返回一个 `MSPProfile`,与下游 `.posixCore` 同级:

```swift
let proxy = ModelShellProxy(configuration: MSPConfiguration(workspace: workspace))
try proxy.enable(MSPBridge.bridgeProfile(config))   // 替代 .posixCore
```

## 两层隔离(实测)

| 层 | 机制 | 适用 | 验证结果 |
| :-- | :-- | :-- | :-- |
| 映射层 | 真进程跑物理工作区,path mapper 虚拟↔物理互转,输出 sanitize | toybox / git | `ls /etc` → `No such file or directory` |
| 拦截层 | 解释器嵌进进程,`os.open` 被 broker 覆盖,open() 走虚拟 FS | python | 读 `/etc/passwd` → `FileNotFoundError`;写 `/tmp/pwn.txt` → 落到工作区虚拟 tmp,真实宿主无此文件 |

## 构建(WSL Ubuntu,Swift 6.1.3)

1. **toybox**:`make defconfig && make` → 二进制;`make install_flat PREFIX=<dir>` → 生成 applet 符号链接(239 个)。
2. **MSP++ Swift**:裁剪版 `Package.swift`(去掉 swift-cgit2 / MSPGit / iOS 专属 / chat / validator → **零网络依赖**);`swift build --product mspxx-smoke`。
3. **python**:系统 `libpython3.14.so`,dlopen 加载。

## 关键修复(相对上游)

1. **Linux CPython dlopen**:上游 `MSPCPythonSymbols.swift` 整个 `#if canImport(Darwin)` 包裹,Linux 直接抛 `engineUnavailable("dynamic CPython loading is not available")`。MSP++ 改为 `#if canImport(Darwin) || canImport(Glibc)`,用 Glibc 的 `dlopen`/`dlsym`。这是作者所说"移植中"的那块。
2. **Windows clone 的 CRLF 污染 shebang**:toybox `genconfig.sh` 变 `#!/bin/bash\r` 使 make 失败,构建前批量 `sed -i 's/\r$//'`。
3. **`toybox --list` 不是合法旗标**:multiplexer 会报 `Unknown command --list`;枚举用**裸 `toybox`** 输出按空白分割。
4. **危险命令黑名单**:`mount/reboot/su/nsenter/pivot_root/...` 等 27 个不注册——真二进制的宿主级操作不能暴露给模型。
5. **`swift build --target X` 不链接可执行 product**,要用 `swift build --product <name>`。

## 验证(mspxx-smoke 冒烟)

| 命令 | 结果 |
| :-- | :-- |
| `ls /` / `cat` / `echo` / `sort` | toybox coreutils ✓ |
| `python3 -c 'print(41+1)'` | 嵌入式 CPython → 42 ✓ |
| `git --version` | 真实 git 2.53.0 ✓ |
| `ls /etc` | 阻断(映射层)✓ |
| python 读 `/etc/passwd` | 阻断(拦截层)✓ |
| python 写 `/tmp/pwn.txt` | 虚拟化进工作区,宿主无落盘 ✓ |

## 与上游 MSP 的差异

| | 上游 MSP | MSP++ |
| :-- | :-- | :-- |
| 命令面 | 手写 Swift 重写 POSIX(117 命令) | 真实宽松运行时(toybox + git + CPython) |
| 隔离 | 语义虚拟 FS(命令天然只在虚拟 FS) | 映射层 + 拦截层 |
| 依赖 | 无(纯 Swift) | toybox 二进制 + 系统 libpython + 真 git |
| 适用 | iOS/嵌入/无真工具环境 | 有真工具的环境(桌面 Linux/macOS) |

MSP++ 的取舍:换来"不手写命令",付出"依赖宿主真二进制 + 映射级隔离(编译程序)不是拦截级"。严格文件层沙箱仍只有 Python(拦截)能做到;toybox/git 要更严需 OS 级沙箱。

## 状态 / 下一步

- ✅ bridge 模块编译通过 + 端到端验证(功能 + 隔离)
- ⬜ 删掉手写 POSIX 命令(只留 shell builtin + bridge)
- ⬜ 接进 pi-shell(替换 fake POSIX 内核)
- ⬜ git 实际工作流 / 管道 / 重定向边界测试

---

*MSP++ 是独立于上游 nian2026/msp 的实验 fork,不代表上游立场。*
