# GN + Ninja 入门实战

> 目标：3 天内真正掌握 GN + Ninja 的工作原理 + 实操细节
> 风格：极度细化，每条命令解释用途
> 不涉及 WebRTC，只训练构建能力
> 每天 3~5 小时

============================================================
DAY 1 —— 完全理解 Ninja（执行层）
============================================================

# 第一部分：安装与验证（30 分钟）

## 1️⃣ 安装

```bash
brew install ninja
```

解释：
- brew = macOS 包管理器
- install ninja = 下载并安装 Ninja 可执行文件


## 2️⃣ 验证

```bash
which ninja
```

作用：查看 ninja 安装路径

```bash
ninja --version
```

作用：验证可执行文件可用


--------------------------------------------------
第二部分：手写第一个 build.ninja（1.5 小时）
--------------------------------------------------

## 1️⃣ 创建目录

```bash
mkdir -p ~/build_training/day1
cd ~/build_training/day1
```

mkdir -p = 如果父目录不存在也创建


## 2️⃣ 创建源码

创建 main.cpp

```cpp
#include <iostream>
int main() {
    std::cout << "Hello Ninja" << std::endl;
    return 0;
}
```


## 3️⃣ 创建 build.ninja

```ninja
rule cxx
  command = clang++ $in -std=c++17 -o $out
  description = Compiling $in

build app: cxx main.cpp
```

解释：

rule cxx
- 定义规则名：cxx

command
- 真正执行的 shell 命令
- $in = 输入文件
- $out = 输出文件

build app: cxx main.cpp
- 目标文件 app
- 使用规则 cxx
- 输入是 main.cpp


## 4️⃣ 执行

```bash
ninja
```

解释：
- Ninja 默认读取当前目录 build.ninja

运行：

```bash
./app
```


--------------------------------------------------
第三部分：多文件 + 依赖理解（2 小时）
--------------------------------------------------

新增 hello.cpp

```cpp
#include <iostream>
void say() {
    std::cout << "Hello From Library" << std::endl;
}
```

修改 main.cpp

```cpp
void say();
int main() {
    say();
}
```


修改 build.ninja

```ninja
rule cxx
  command = clang++ $in -std=c++17 -o $out

build app: cxx main.cpp hello.cpp
```


重新构建：

```bash
ninja -t clean
ninja
```

解释：
- -t clean = 清理产物


📌 重要理解：
Ninja 不做自动头文件扫描
Ninja 不理解 C++
Ninja 只执行规则


============================================================
DAY 2 —— 引入 GN（规则生成层）
============================================================

# 第一部分：安装 GN（30 分钟）

```bash
brew install gn

或者二进制方式：
curl -L "https://chrome-infra-packages.appspot.com/dl/gn/gn/mac-amd64/+/latest" \
  -o gn.zip
unzip gn.zip -d /tmp/gn-bin
sudo mv /tmp/gn-bin/gn /usr/local/bin/gn
sudo chmod +x /usr/local/bin/gn

```

验证：

```bash
gn --version
```


--------------------------------------------------
第二部分：最小 GN 工程（2 小时）
--------------------------------------------------

## 1️⃣ 创建目录

```bash
mkdir -p ~/build_training/day2
cd ~/build_training/day2
```


## 2️⃣ 创建 .gn 文件

```gn
buildconfig = "//BUILD.gn"
```

解释：
- 告诉 GN 默认配置文件位置


## 3️⃣ 创建 BUILD.gn

```gn
executable("app") {
  sources = [ "main.cpp" ]
}
```

解释：
- executable = 生成可执行文件
- "app" = target 名称
- sources = 编译源文件列表


## 4️⃣ 创建 main.cpp

```cpp
#include <iostream>
int main() {
    std::cout << "Hello GN" << std::endl;
}
```


## 5️⃣ 生成 Ninja 文件

```bash
gn gen out
```

解释：
- gen = 生成构建文件
- out = 输出目录

查看：

```bash
ls out
```

你会看到 build.ninja


## 6️⃣ 构建

```bash
ninja -C out
```

解释：
- -C out = 切换到 out 目录执行

运行：

```bash
./out/app
```


--------------------------------------------------
第三部分：静态库拆分（2 小时）
--------------------------------------------------

创建 hello.h

```cpp
#pragma once
void say();
```

hello.cpp

```cpp
#include <iostream>
void say() {
    std::cout << "Hello Library" << std::endl;
}
```

修改 main.cpp

```cpp
#include "hello.h"
int main() {
    say();
}
```


修改 BUILD.gn

```gn
static_library("hello_lib") {
  sources = [ "hello.cpp" ]
}

executable("app") {
  sources = [ "main.cpp" ]
  deps = [ ":hello_lib" ]
}
```

解释：

static_library
- 生成 .a 文件

:hello_lib
- 当前目录 target


重新生成：

```bash
gn gen out
ninja -C out
```


📌 关键理解：
GN 负责构建图
Ninja 负责执行图


============================================================
DAY 3 —— 工程化能力强化
============================================================

# 第一部分：构建参数系统（2 小时）

## 1️⃣ 生成 Debug

```bash
gn gen out/debug --args='is_debug=true'
```

## 2️⃣ 生成 Release

```bash
gn gen out/release --args='is_debug=false'
```


## 3️⃣ 查看可用参数

```bash
gn args out/debug --list
```


--------------------------------------------------
第二部分：自定义 config（1.5 小时）
--------------------------------------------------

在 BUILD.gn 添加：

```gn
config("warning_config") {
  cflags = [ "-Wall", "-Wextra" ]
}

executable("app") {
  sources = [ "main.cpp" ]
  configs += [ ":warning_config" ]
}
```

解释：

config
- 可复用编译参数集合

configs +=
- 给当前 target 添加配置


--------------------------------------------------
第三部分：多目录工程（1.5 小时）
--------------------------------------------------

目录结构：

src/core/
src/net/
src/ui/

每个目录 BUILD.gn 示例：

```gn
static_library("core") {
  sources = [ "core.cpp" ]
}
```

顶层 BUILD.gn：

```gn
executable("app") {
  sources = [ "main.cpp" ]
  deps = [
    "//src/core",
  ]
}
```

解释：

// 表示工程根路径


--------------------------------------------------
第四部分：生成 Xcode 工程（1 小时）
--------------------------------------------------

```bash
gn gen out/xcode --ide=xcode
open out/xcode/all.xcodeproj
```

解释：
--ide=xcode = 生成 Xcode 工程描述


============================================================
三天后能力模型
============================================================

你现在应该可以：

✔ 手写 Ninja 文件
✔ 理解 rule / build
✔ 编写 GN target
✔ 组织静态库
✔ 管理编译参数
✔ 管理多目录工程
✔ 生成 IDE 工程


如果你想继续，我可以带你做：

- iOS/mac Bundle 构建实战
- GN 高级语法（template / group）
- 或进入 WebRTC 构建实战

你下一步想强化哪块？

