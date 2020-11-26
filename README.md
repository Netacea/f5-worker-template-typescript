# Netacea F5 Worker Template
![Netacea Header](https://assets.ntcacdn.net/header.jpg)
[![TypeScript](https://img.shields.io/badge/%3C%2F%3E-TypeScript-%230074c1.svg)](http://www.typescriptlang.org/)

An F5 IRules LX Workspace to add Netacea functionality to F5.

## 💡 Getting Started
There are 2 ways to get started
### 🎂 Prebuilt Package
Download the latest package from the [releases](https://github.com/Netacea/f5-worker-template-typescript/releases) page.
Then see the [upload](https://github.com/Netacea/f5-worker-template-typescript/wiki/IRules-LX#upload-workspace) section of our wiki.

After uploading the workspace, under `Local Traffic > iRules > LX Workspaces` click on the `Netacea` LX Workspace. In `Workspace Files` there will be a netacea directory with a `NetaceaConfig.json` in there - place your `apiKey` and `secretKey` in respective places in this JSON file.

### 🛠 DIY
Ensure the `@netacea/f5` package is up to date by running:
```bash
npm i @netacea/f5@latest
```
Insert your Netacea API and Secret key into `./src/NetaceaConfig.json`.

Then run
```bash
npm run build
```
This will create a GZipped workspace ready to [upload](https://github.com/Netacea/f5-worker-template-typescript/wiki/IRules-LX#upload-workspace

## ❗ Issues
If you run into issues with this specific project, please feel free to file an issue [here](https://github.com/Netacea/f5-worker-template-typescript/issues).