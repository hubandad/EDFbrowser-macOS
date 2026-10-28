# 🧠 EDFbrowser for macOS (Apple Silicon)

This guide provides detailed instructions on how to compile **EDFbrowser** from source on Mac computers equipped with **Apple Silicon (M1/M2/M3/M4)** chips. 

> [!TIP]
> For a Chinese Version please refer to **[This](https://github.com/hubandad/EDFbrowser-macOS/blob/main/README-CN.md)**.

> [!IMPORTANT]
> Applicable Systems: macOS 15 Sequoia (compatible with Ventura / Sonoma)
>
> Reference: Compiling EDFBrowser Mac Oct 2024

------

## 📋 Table of Contents

- [Prerequisites & Warnings](https://www.google.com/search?q=%23-前置要求--警告)
- [1. Setting up the Environment](https://www.google.com/search?q=%231-准备开发环境)
- [2. Getting the Source Code](https://www.google.com/search?q=%232-获取源码)
- [3. Modifying Source Code (Critical)](https://www.google.com/search?q=%233-源码修改-关键步骤)
- [4. Build & Compile](https://www.google.com/search?q=%234-编译构建)
- [5. Run & Install](https://www.google.com/search?q=%235-运行与安装)
- [Troubleshooting](https://www.google.com/search?q=%23-常见问题排查-troubleshooting)

------

## 🛑 Prerequisites & Warnings

Please carefully read the following compatibility warnings before starting.

> [!WARNING]
>
> Strictly avoid mixing Homebrew and MacPorts Qt libraries!
>
> - This tutorial **requires** installing Qt5 via **MacPorts**.
> - If you already have Qt installed via Homebrew, ensure you specify the MacPorts path strictly during compilation; otherwise, `qmake` conflicts will cause build failures.

**System Requirements:**

- **Hardware**: Apple Silicon (M-series chips)
- **OS**: macOS Ventura / Sonoma / Sequoia
- **Tools**:
  - Xcode 16 + Command Line Tools
  - MacPorts
  - Qt5 (via MacPorts)

------

## 1. Setting up the Environment

### 1.1 Install Xcode Command Line Tools

Open Terminal and execute the following command to install the basic compilation tools:

Bash

```
xcode-select --install
```

Verify installation:

Bash

```
xcode-select -p
# Output should look like: /Library/Developer/CommandLineTools
```

### 1.2 Install MacPorts

Go to the official website, download the installer for your specific OS version, and install it:

🔗 Download Link: MacPorts Installation

Verify installation:

Bash

```
port version
```

### 1.3 Install Qt5 (Must use MacPorts)

This is the most critical step. Please execute:

Bash

```
sudo port install qt5-qtbase
```

**Verify Path** (Make sure the path is `/opt/local/...`):

Bash

```
/opt/local/libexec/qt5/bin/qmake -v
```

*Expected output:* `QMake version 3.xxx` and `Using Qt version 5.15.15`.

------

## 2. Getting the Source Code

Visit the official EDFbrowser website to download the latest source code (using version 2.14 as an example):

🔗 Official Site: http://www.teuniz.net/edfbrowser/

After downloading `edfbrowser_214_source.tar.gz`, create a working directory and extract the files:

Bash

```
# Create and enter working directory
mkdir ~/test_edfbrowser
cd ~/test_edfbrowser

# Assuming the downloaded file is in the Downloads folder
mv ~/Downloads/edfbrowser_214_source.tar.gz .

# Extract
tar -zxvf edfbrowser_214_source.tar.gz

# Enter source folder
cd edfbrowser_214_source
```

------

## 3. Modifying Source Code (Critical)

> [!IMPORTANT]
>
> For version 2.11 and above, you must modify the global.h file; otherwise, compilation will fail immediately.

Open `global.h` with any text editor and locate **Line 56**.

**Before modification:**

C++

```
#error "configuration error"
```

**After modification (comment out the line):**

C++

```
// #error "configuration error"
```

Save and exit the editor.

------

## 4. Build & Compile

### 4.1 Generate Makefile

**Note**: You must use the full path to call MacPorts' `qmake`. Do not type `qmake` directly (to avoid calling the system default version).

Bash

```
/opt/local/libexec/qt5/bin/qmake
```

### 4.2 Start Compilation

Use multi-core compilation (`-j8` uses 8 threads; adjust according to your computer's performance):

Bash

```
make -j8
```

> 📝 **Tip**: You may see some Warning messages from third-party libraries during compilation. This is normal; please ignore them.

------

## 5. Run & Install

### Test Run

After compilation is complete, `EDFbrowser.app` will be generated in the directory.

Bash

```
open ./EDFbrowser.app
```

If the GUI window pops up successfully, congratulations, the build succeeded! 🎉

### Install to Applications Folder (Optional)

Move it to the system applications directory to use it like a regular App:

Bash

```
mv ./EDFbrowser.app /Applications/
```

------

## 🔧 Troubleshooting

If you encounter issues during the compilation process, please check the following points:

<details>

<summary><strong>❌ Error: qmake command not found</strong></summary>

Most likely, Qt5 is not installed. Please run:

<code>sudo port install qt5-qtbase</code>

</details>

<details>

<summary><strong>❌ Error: Library version mismatch during compilation</strong></summary>

Please check the qmake path you are using:

<code>which qmake</code>

If the output is not /opt/local/libexec/qt5/bin/qmake, you are using the wrong version. Be sure to use the absolute path when running qmake.

</details>

<details>

<summary><strong>❌ Error: Xcode select error</strong></summary>

Even if Xcode is installed, you sometimes need to relink the Command Line Tools:

<code>xcode-select --install</code>

</details>

------

## 📚 References

- Original Guide: [Compiling EDFBrowser Mac Oct 2024](https://doi.org/10.13140/RG.2.2.16201.15208)
