# DAY 4 ——  多目录工程（扩展版）

本章节目标：从单目录 BUILD.gn 过渡到 **真实项目结构**，理解 GN
在大型工程中的组织方式（例如 Chromium / WebRTC 类似的结构）。

学习目标：

-   理解多目录 BUILD.gn 协作
-   掌握 GN label 依赖
-   理解 deps / public_deps
-   掌握 visibility 依赖控制
-   学会 config 共享编译参数
-   理解 include_dirs 与 toolchain 的关系
-   构建完整多模块工程

------------------------------------------------------------------------

# 最终工程结构

    project/
    │
    ├─ .gn
    ├─ BUILDCONFIG.gn
    ├─ BUILD.gn
    │
    ├─ app/
    │  ├─ BUILD.gn
    │  └─ main.cpp
    │
    ├─ hello/
    │  ├─ BUILD.gn
    │  ├─ hello.cpp
    │  └─ hello.h
    │
    └─ util/
       ├─ BUILD.gn
       ├─ util.cpp
       └─ util.h

构建关系：

    app
     └── hello_lib
            └── util_lib

------------------------------------------------------------------------

# 阶段1：拆分目录（20min）

目标：理解 BUILD.gn 可以存在于任意目录。

GN 会自动递归解析 BUILD.gn 文件。

## project/.gn
    buildconfig = "//BUILDCONFIG.gn"

## project/BUILDCONFIG.gn
    set_default_toolchain("//:default")

## project/BUILD.gn
    toolchain("default") {

      toolchain_args = {
        current_os = host_os
        current_cpu = host_cpu
      }

      tool("cc") {
        command = "clang -c {{source}} {{defines}} {{include_dirs}} {{cflags}} -o {{output}}"
        outputs = [ "{{source_out_dir}}/{{source_name_part}}.o" ]
      }

      tool("cxx") {
        command = "clang++ -c {{source}} {{defines}} {{include_dirs}} {{cflags_cc}} -o {{output}}"
        outputs = [ "{{source_out_dir}}/{{source_name_part}}.o" ]
      }

      tool("alink") {
        command = "ar rcs {{output}} {{inputs}}"
        outputs = [ "{{root_out_dir}}/lib{{target_output_name}}.a" ]
        default_output_dir = "{{root_out_dir}}"
      }

      tool("link") {
        command = "clang++ {{inputs}} -o {{output}}"
        outputs = [ "{{root_out_dir}}/{{target_output_name}}" ]
        default_output_dir = "{{root_out_dir}}"
      }
    }

    group("default") {
      deps = [
        "//app:app",
      ]
    }


## hello/BUILD.gn

    static_library("hello_lib") {
      sources = [
        "hello.cpp",
      ]

      public = [
        "hello.h",
      ]

      deps = [
        "//util:util_lib",
      ]

      public_configs = [ ":hello_config" ]
    }

    config("hello_config") {
      include_dirs = [ "." ]
    }

------------------------------------------------------------------------

# 阶段2：增加 util 模块（20min）

util/BUILD.gn

    config("util_config") {
      include_dirs = [ "." ]
    }

    static_library("util_lib") {
      sources = [
        "util.cpp",
      ]

      public = [ "util.h" ]

      public_configs = [ ":util_config" ]
    }

util.cpp

    #include "util.h"

    const char* util_name() {
        return "Utility";
    }

util.h

    #pragma once
    const char* util_name();

------------------------------------------------------------------------

# 阶段3：app 依赖 hello（20min）

app/BUILD.gn

    executable("app") {
      sources = [
        "main.cpp",
      ]

      deps = [
        "//hello:hello_lib",
      ]
    }

main.cpp

    #include "hello.h"

    int main() {
        say_hello();
    }

------------------------------------------------------------------------

# 阶段4：理解 GN label（15min）

GN 使用 label 表示 target。

    "//dir:target"

示例：

    "//hello:hello_lib"

含义：

    root
     └─ hello
          └─ BUILD.gn
               └─ target hello_lib

常见写法：

  写法          含义
  ------------- ---------------
  :lib          当前 BUILD.gn
  //hello:lib   hello 目录
  //hello       默认 target
  ../lib:util   相对路径

------------------------------------------------------------------------

# 阶段5：visibility（15min）

控制模块访问权限。

    static_library("util_lib") {
      sources = [ "util.cpp" ]

      visibility = [
        "//hello:*",
      ]
    }

这样 app 不能直接依赖 util。

------------------------------------------------------------------------

# 阶段6：public_deps（10min）

默认依赖不会传播头文件路径。

    A -> B -> C

A 看不到 C。

使用 public_deps：

    static_library("hello_lib") {
      sources = [ "hello.cpp" ]

      public_deps = [
        "//util:util_lib",
      ]
    }

依赖传播：

    app -> hello -> util

app 可以 include util.h。

------------------------------------------------------------------------

# 阶段7：config 共享编译参数（10min）

根 BUILD.gn：

    config("global_config") {
      cflags_cc = [
        "-std=c++17",
      ]
    }

模块引用：

    configs += [ "//:global_config" ]

------------------------------------------------------------------------

# 阶段8：include_dirs 与 toolchain（重要）

自定义 toolchain 时必须把 include 参数传给编译器。

示例：

    tool("cxx") {
      command = "clang++ -c {{source}} {{defines}} {{include_dirs}} {{cflags}} {{cflags_cc}} -o {{output}}"
      outputs = [ "{{source_out_dir}}/{{source_name_part}}.o" ]
    }

否则：

    fatal error: header file not found

因为 GN 不会自动把 include_dirs 传给编译器。

------------------------------------------------------------------------

# 阶段9：最终构建图

执行：

    gn gen out
    ninja -C out

构建图：

    util.cpp
       ↓
    libutil_lib.a

    hello.cpp
       ↓
    libhello_lib.a

    main.cpp
       ↓
    app

运行：

    ./out/app

输出：

    Hello GN + Utility

------------------------------------------------------------------------

# 本章节掌握的核心能力

-   多目录 BUILD.gn
-   label 依赖系统
-   deps / public_deps
-   visibility
-   config 参数共享
-   include_dirs 与 toolchain
-   GN 构建图结构

完成本章节后，你已经可以搭建一个 **接近真实 GN 项目的结构**。



生成 Xcode 工程 

```bash
gn gen out/xcode --ide=xcode
open out/xcode/all.xcodeproj
```

解释：
--ide=xcode = 生成 Xcode 工程描述



