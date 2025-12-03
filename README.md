# EDFbrowser-macOS
EDFbrowser macOS M芯片电脑编译教程



## ✅ 在 M 芯片 Mac 上编译 EDFBrowser 的完整流程

适用系统：
	•	macOS 15 Sequoia（或 Ventura / Sonoma）
	•	Apple Silicon：M1 / M2 / M3 /M4
	•	Xcode 16（含 CommandLine Tools）
	•	MacPorts + Qt5（必须用 MacPorts，不能用 Homebrew！）

⚠️注意：不能混用 Homebrew 和 MacPorts 的 Qt，否则 qmake 会冲突、导致无法成功编译。PDF 中明确要求使用 MacPorts 版本的 Qt5。



## 📌 一、安装并准备开发环境

1. 安装 Xcode Command Line Tools

`` xcode-select --install ``

安装完成后可检查：

`` xcode-select -p ``




2. 安装 MacPorts（必须）

前往：https://www.macports.org/install.php

根据你系统版本下载对应的 pkg。
安装后检查：

`` port version ``




3. 安装 Qt5（版本例如 5.15.15）

必须使用 MacPorts 提供的 Qt5，否则会混库导致编译失败（PDF 强调这一点）。

执行：

`` sudo port install qt5-qtbase ``

安装完成后确认 qmake 路径：

`` /opt/local/libexec/qt5/bin/qmake -v ``

结果应类似：

`` QMake version 3.xxx
Using Qt version 5.15.15 ... ``

一定要使用这个 qmake 的 FULL PATH，后续编译不能使用系统/其它渠道的 qmake。



## 📌 二、下载 EDFBrowser 源码

4. 下载源码（以 2.14 为例）

前往：
`` http://www.teuniz.net/edfbrowser/ ``

下载：

`` edfbrowser_214_source.tar.gz ``

假设下载后放在 ~/Downloads/。



## 📌 三、解压并进入源码目录

5. 创建工作目录

`` mkdir ~/test_edfbrowser ``
`` cd ~/test_edfbrowser ``

6. 将压缩包移动进来

`` mv ~/Downloads/edfbrowser_214_source.tar.gz . ``

7. 解压

`` tar -zxvf edfbrowser_214_source.tar.gz ``

系统会列出大量文件。



## 📌 四、修改源码（PDF 指定必要修改）

8. 进入源码目录

`` cd edfbrowser_214_source ``

9. 修改 global.h（这是 PDF 中特别强调的关键步骤）

打开 global.h，找到 第 56 行：

原本是：

`` #error "configuration error" ``

改成（注释掉）：

`` // #error "configuration error" ``

保存退出。

这是为 2.11+ 版本必要的修改，否则会直接编译失败。



## 📌 五、编译 EDFBrowser

10. 使用 MacPorts 的 Qt5 qmake（必须全路径！）

PDF 强调要避免库混用，因此绝不能用系统自动找到的 qmake。

执行：

`` /opt/local/libexec/qt5/bin/qmake ``

qmake 执行完后你会看到项目 Makefile 已生成。


11. 开始编译

`` make -j8 ``

编译过程中可能有一些第三方库的警告，PDF 说明这些都不严重，忽略即可。


## 📌 六、测试运行

12. 执行 EDFbrowser

`` open ./EDFbrowser.app ``

如果成功，会弹出 EDFbrowser GUI 窗口，表示编译成功 🎉


## 📌 七、可选：将 app 移动到应用程序文件夹

`` mv ./EDFbrowser.app /Applications/ ``

即可像普通应用一样打开。


## 📌 八、（补充）常见问题说明

这些并不是 PDF 原文内容，但对你编译成功非常重要——我单独列出，方便排错：

1. qmake 命令找不到？

大概率是因为你没有安装 Qt5：

`` sudo port install qt5-qtbase ``


2. qmake 不是 MacPorts 版本？

检查 qmake 路径：

`` which qmake ``

如果输出不是 /opt/local/...，你一定要使用 PDF 指定路径：

`` /opt/local/libexec/qt5/bin/qmake ``


3. 提示 xcode-select 错误

安装 command line tools 即可：

`` xcode-select --install ``


🎉 完成！


## 参考文献：[Compiling EDFBrowser Mac Oct 2024 ](https://doi.org/10.13140/RG.2.2.16201.15208)
