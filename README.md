<p align="center">
  <img src="documentation-images/README-header.gif" alt="">
</p>
<p align="center">
  This is <strong>my local configuration</strong>.
</p>

- - -

## 📝 Table of contents
- [**Prerequisites**](#prerequisites)
- [**Commands**](#commands)
- [**Software manual configuration**](#software-manual-configuration)
  - [**Fonts**](#fonts)
  - [**Sublime Text**](#sublime-text)
  - [**Firefox**](#firefox)
  - [**Google Chrome**](#google-chrome)
  - [**Thunderbird**](#thunderbird)
- [**License**](#license)

- - -

<a name="prerequisites"></a>
## ⚙️ Prerequisites
- [**asdf**](https://github.com/asdf-vm/asdf)
- [**Antibody**](https://getantibody.github.io/)

<a name="commands"></a>
## ⌨️ Commands
### Install
```makefile
## Create symbolic links for files/folders with a .symlink suffix

make links
```

💡 Symbolic links are created between `$PWD/[file-or-folder].symlink` and `$HOME/.[file-or-folder]`.

### Help
```makefile
## List available commands

make help
```

<a name="software-manual-configuration"></a>
## 🔧 Software manual configuration

<a name="fonts"></a>
### Fonts
The monospace font I use for coding is [**Cascadia Code**](https://github.com/microsoft/cascadia-code).

<a name="sublime-text"></a>
### Sublime Text
Install [**Package Control**](https://packagecontrol.io/installation)

<a name="firefox"></a>
### Firefox
1. Disable HTTP Cache when toolbox is open
2. Set Firefox as default browser

<a name="google-chrome"></a>
### Google Chrome
Disable Chrome cache while DevTools is open

<a name="thunderbird"></a>
### Thunderbird
Set a [mail signature](https://github.com/wearemd/mail-signatures) for each account

<a name="license"></a>
## 📄 License
**My dotfiles** are licensed under the [GNU General Public License v3.0](LICENSE).
