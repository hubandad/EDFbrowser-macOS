# 🧠 EDFbrowser for macOS (Apple Silicon)

[](https://www.apple.com/mac/)
[](https://www.google.com/search?q=)
[](https://www.macports.org/)

本指南详细介绍了如何在搭载 **Apple Silicon (M1/M2/M3/M4)** 芯片的 Mac 电脑上，从源码编译 **EDFbrowser**。

> **适用系统**：macOS 15 Sequoia (兼容 Ventura / Sonoma)
> **参考来源**：[Compiling EDFBrowser Mac Oct 2024](https://doi.org/10.13140/RG.2.2.16201.15208)

-----

## 📋 目录 (Table of Contents)

  - [前置要求 & 警告](https://www.google.com/search?q=%23-%E5%89%8D%E7%BD%AE%E8%A6%81%E6%B1%82--%E8%AD%A6%E5%91%8A)
  - [1. 准备开发环境](https://www.google.com/search?q=%231-%E5%87%86%E5%A4%87%E5%BC%80%E5%8F%91%E7%8E%AF%E5%A2%83)
  - [2. 获取源码](https://www.google.com/search?q=%232-%E8%8E%B7%E5%8F%96%E6%BA%90%E7%A0%81)
  - [3. 源码修改 (关键步骤)](https://www.google.com/search?q=%233-%E6%BA%90%E7%A0%81%E4%BF%AE%E6%94%B9-%E5%85%B3%E9%94%AE%E6%AD%A5%E9%AA%A4)
  - [4. 编译构建](https://www.google.com/search?q=%234-%E7%BC%96%E8%AF%91%E6%9E%84%E5%BB%BA)
  - [5. 运行与安装](https://www.google.com/search?q=%235-%E8%BF%90%E8%A1%8C%E4%B8%8E%E5%AE%89%E8%A3%85)
  - [常见问题排查 (Troubleshooting)](https://www.google.com/search?q=%23-%E5%B8%B8%E8%A7%81%E9%97%AE%E9%A2%98%E6%8E%92%E6%9F%A5-troubleshooting)

-----

## 🛑 前置要求 & 警告

在开始之前，请务必阅读以下兼容性警告。

> [\!WARNING]
> **严禁混用 Homebrew 和 MacPorts 的 Qt 库！**
>
>   * 本教程**必须**使用 **MacPorts** 安装 Qt5。
>   * 如果你系统中已通过 Homebrew 安装了 Qt，请确保在编译时严格指定 MacPorts 的路径，否则 `qmake` 会发生冲突导致编译失败。

**环境需求：**

  * **硬件**：Apple Silicon (M 系列芯片)
  * **系统**：macOS Ventura / Sonoma / Sequoia
  * **工具**：
      * Xcode 16 + Command Line Tools
      * MacPorts
      * Qt5 (via MacPorts)

-----

## 1\. 准备开发环境

### 1.1 安装 Xcode Command Line Tools

打开终端，执行以下命令安装基础编译工具：

```bash
xcode-select --install
```

验证安装：

```bash
xcode-select -p
# 输出应类似：/Library/Developer/CommandLineTools
```

### 1.2 安装 MacPorts

前往官方网站下载对应系统版本的安装包并安装：
🔗 **下载地址**：[MacPorts Installation](https://www.macports.org/install.php)

验证安装：

```bash
port version
```

### 1.3 安装 Qt5 (必须使用 MacPorts)

这是最关键的一步，请执行：

```bash
sudo port install qt5-qtbase
```

**验证路径**（务必确认路径为 `/opt/local/...`）：

```bash
/opt/local/libexec/qt5/bin/qmake -v
```

*预期输出：* `QMake version 3.xxx` 和 `Using Qt version 5.15.15`。

-----

## 2\. 获取源码

前往 EDFbrowser 官网下载最新源码（以 2.14 版本为例）：
🔗 **官网**：[http://www.teuniz.net/edfbrowser/](http://www.teuniz.net/edfbrowser/)

下载 `edfbrowser_214_source.tar.gz` 后，建立工作目录并解压：

```bash
# 创建并进入工作目录
mkdir ~/test_edfbrowser
cd ~/test_edfbrowser

# 假设下载文件在 Downloads 文件夹
mv ~/Downloads/edfbrowser_214_source.tar.gz .

# 解压
tar -zxvf edfbrowser_214_source.tar.gz

# 进入源码文件夹
cd edfbrowser_214_source
```

-----

## 3\. 源码修改 (关键步骤)

> [\!IMPORTANT]
> 对于 2.11 及以上版本，**必须**修改 `global.h` 文件，否则编译将直接报错。

使用任意文本编辑器打开 `global.h`，定位到 **第 56 行**。

**修改前：**

```cpp
#error "configuration error"
```

**修改后（注释掉该行）：**

```cpp
// #error "configuration error"
```

保存并退出编辑器。

-----

## 4\. 编译构建

### 4.1 生成 Makefile

**注意**：必须使用全路径调用 MacPorts 的 `qmake`，切勿直接输入 `qmake`（以免调用系统默认版本）。

```bash
/opt/local/libexec/qt5/bin/qmake
```

### 4.2 开始编译

使用多核编译（`-j8` 表示使用 8 个线程，可根据电脑性能调整）：

```bash
make -j8
```

> 📝 **提示**：编译过程中可能会出现一些第三方库的 Warning 警告，这属于正常现象，请忽略。

-----

## 5\. 运行与安装

### 测试运行

编译完成后，目录中会生成 `EDFbrowser.app`。

```bash
open ./EDFbrowser.app
```

如果 GUI 窗口成功弹出，恭喜你，编译成功！🎉

### 安装到应用程序文件夹 (可选)

将其移动到系统应用目录，以便像普通 App 一样使用：

```bash
mv ./EDFbrowser.app /Applications/
```

-----

## 🔧 常见问题排查 (Troubleshooting)

如果在编译过程中遇到问题，请检查以下几点：

\<details\>
\<summary\>\<strong\>❌ 错误：qmake command not found\</strong\>\</summary\>

大概率是因为没有安装 Qt5。请运行：
\<code\>sudo port install qt5-qtbase\</code\>

\</details\>

\<details\>
\<summary\>\<strong\>❌ 错误：编译时提示库版本不匹配\</strong\>\</summary\>

请检查你使用的 `qmake` 路径：
\<code\>which qmake\</code\>
如果输出不是 `/opt/local/libexec/qt5/bin/qmake`，说明你用错了版本。请务必使用**绝对路径**运行 qmake。

\</details\>

\<details\>
\<summary\>\<strong\>❌ 错误：Xcode select error\</strong\>\</summary\>

即使安装了 Xcode，有时也需要重新链接 Command Line Tools：
\<code\>xcode-select --install\</code\>

\</details\>

-----

## 📚 参考文献

  * Original Guide: [Compiling EDFBrowser Mac Oct 2024](https://doi.org/10.13140/RG.2.2.16201.15208)
