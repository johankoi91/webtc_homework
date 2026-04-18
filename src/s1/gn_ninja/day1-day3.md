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
buildconfig = "//BUILDCONFIG.gn"
```

解释：
- 告诉 GN 默认配置文件位置

## 2️⃣ 创建 BUILDCONFIG.gn 文件
```gn
set_default_toolchain("//:default")
```
GN 会：
查找 label //:default
加载 BUILD.gn
找到：toolchain("default") { ... }, 初始化该 toolchain,
把 executable("app") 绑定到这个 toolchain


## 3️⃣ 创建 BUILD.gn

```gn
toolchain("default") {

  toolchain_args = {
    current_os = host_os
    current_cpu = host_cpu
  }

  tool("cc") {
    command = "clang -c {{source}} -o {{output}}"
    outputs = [ "{{source_out_dir}}/{{source_name_part}}.o" ]
    default_output_extension = ".o"
  }

  tool("cxx") {
    command = "clang++ -c {{source}} -o {{output}}"
    outputs = [ "{{source_out_dir}}/{{source_name_part}}.o" ]
    default_output_extension = ".o"
  }

  tool("link") {
    command = "clang++ {{inputs}} -o {{output}}"
    outputs = [ "{{root_out_dir}}/{{target_output_name}}" ]
    default_output_dir = "{{root_out_dir}}"
  }
}

executable("app") {
  sources = [ "main.cpp" ]
}
```

substitution 变量系统
在 tool() 里：

command = "clang++ {{inputs}} -o {{output}}"

{{xxx}} 是 GN 的 substitution pattern。

它们不是普通变量，而是：

由 GN 在生成 build.ninja 阶段替换

你当前用到的：
substitution	含义
{{source}}	当前源文件
{{inputs}}	所有输入文件
{{output}}	当前输出文件
{{source_name_part}}	文件名不带扩展名
{{source_out_dir}}	对应 obj 目录
{{root_out_dir}}	out 目录
{{target_output_name}}	目标名

曾经出现：
clang++ obj/main.o -o /app

原因是：
自定义 toolchain
没定义 default_output_dir
GN 无法推导输出目录，fallback 成 /

现在写：
outputs = [ "{{root_out_dir}}/{{target_output_name}}" ]
default_output_dir = "{{root_out_dir}}"
GN 会把：
root_out_dir = out
所以生成：
out/app


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

这份 BUILD.gn 的真实执行链

当你执行：

gn gen out

GN 做的事情：

解析 toolchain

解析 executable

计算 app 的输出：

root_out_dir = out
target_output_name = app
=> out/app

写入 build.ninja

当你执行：

ninja -C out

执行链：

main.cpp
   ↓ cxx tool
obj/main.o
   ↓ link tool
out/app

完全由你定义的 toolchain 控制。

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


修改 BUILD.gn，增加以下内容

```gn
tool("alink") {
    command = "ar rcs {{output}} {{inputs}}"
    outputs = [ "{{root_out_dir}}/lib{{target_output_name}}.a" ]
    default_output_extension = ".a"
    default_output_dir = "{{root_out_dir}}"
}

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


static_library 这种 target 类型 必须使用 alink tool，

GN 的 target → tool 对应关系

GN 内部每种 target 类型都会映射到特定 tool。

常见映射：

target	使用 tool
executable	link
static_library	alink
shared_library	solink
source 编译	cc / cxx
group	stamp

这里有个很重要的 GN 架构思想
GN 不是根据 target 类型自动生成规则。
而是：

target type
      ↓
tool name
      ↓
toolchain 里的 tool()

也就是说：
static_library → alink
shared_library → solink
executable → link

这些 必须在 toolchain 定义。

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





