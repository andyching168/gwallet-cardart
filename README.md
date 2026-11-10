# gwallet-cardart

**不用 Hook 就能替換 Google 錢包（Google Wallet）卡面**的 KernelSU / Magisk 模組，附 WebUI 可以直接在手機上選圖、套用和還原。

> Replace Google Wallet card art on a rooted Android phone **without hooking** Wallet or Google Play services. It only rewrites Wallet's local image cache. A WebUI lets you pick images, toggle and restore per card. [English summary below](#english).

- ✅ 不注入 Wallet 或 GMS，不需要 LSPosed / Zygisk
- ✅ 嗶卡畫面也會顯示新卡面（實測支付卡）
- ✅ 被重新下載時自動換回自訂圖
- ✅ WebUI：列出卡片、從手機選圖、拖曳裁切、一鍵還原
- ✅ 只改變**顯示**，不碰卡片資料和付款流程

## 原理

Google 錢包用 [Glide](https://github.com/bumptech/glide) 載入卡面，下載的圖片存在：

```
/data/data/com.google.android.apps.walletnfcrel/cache/image_manager_disk_cache/<key>.0
```

其中 **`<key>` = sha256(卡面網址)**，沒有額外的簽章或驗證。只要卡面網址不變，Wallet 就一直讀本機快取，不會重新下載。

這個模組會：

1. 從 Wallet 的卡片紀錄（`files/common/*/*/*.pb`）和 GMS 的 `pay` 資料庫找出卡面網址，算出對應的快取檔名。
2. 第一次套用時備份原圖，再用自訂圖**原地覆寫**快取檔。這樣檔案的擁有者、權限和 SELinux 標籤都不會變。
3. 背景用 `inotifyd` 監看快取資料夾。Glide 寫入新檔（先寫 `.tmp` 再改名）時，馬上換回自訂圖。
4. 同一張原圖如果有多份快取（不同網址），會一起替換。

## 需求

- 已 root 的 Android，使用 KernelSU（或分支）或 Magisk。WebUI 需要支援模組 WebUI 的管理器，例如 KernelSU / SukiSU / KernelSU Next，或在 Magisk 上用 [WebUI X](https://github.com/MMRLApp/WebUI-X-Portable) 這類工具。
- Google 錢包能正常使用（要感應付款，Play Integrity 得自己處理）。

## 安裝

1. 從 [Releases](../../releases) 下載 `gwallet-cardart-v*.zip`，或自行執行 `./build.sh` 打包（App：`app/build.sh`，不需要 Gradle）。
2. 在 KernelSU / Magisk 管理器安裝後重新開機。
3. 先打開一次 Google 錢包並瀏覽你的卡片，讓卡面先下載到快取。

## 使用

開啟模組的 **WebUI**：

- 列表會顯示快取中長寬比像卡片的圖片。能辨識來源的會標上類型（iPASS、支付卡等），名稱可以自己改。
- **選擇圖片**：可以用系統檔案選擇器，或輸入 `/sdcard/...` 路徑。選好後能拖曳、縮放，預設沿用原卡的圓角和透明區。輸出尺寸是原圖的 2 倍。
- **開關**：套用或還原原始卡面。自訂圖會保留，可以隨時再開。
- **刪除自訂**：還原原圖並刪掉自訂圖。
- **重啟 Wallet**：清掉 Wallet 記憶體裡的快取，重新打開就會看到新卡面。

模組列表的 **Action** 按鈕會立刻套用一次並關閉 Wallet。

狀態存在 `/data/adb/wallet_cardart/`（模組更新時保留），紀錄檔在 `log.txt`。**解除安裝模組時會自動還原所有原始卡面。**

## 臨時 root 使用者：單次版 App

如果你用的是**不解鎖 Bootloader 的臨時 root**（例如利用核心漏洞取得 root，重開機後就消失），可以改用 `gwallet-cardart-app-*.apk`：

- 不需要安裝模組，也沒有背景監看。在有 root 的時候**寫入一次**就好。
- 介面和 WebUI 相同，另外多一個「全部重新套用」按鈕。
- 取得 root 後，先在 root 管理器裡允許「Wallet 卡面」使用 su，再打開 App 選圖並套用。

**為什麼寫一次就夠？** Glide 的快取 key 只有網址的 sha256，沒有時間戳或簽章，所以重開機後快取檔還在，Wallet 也會繼續讀它（已實測）。即使之後完全沒有 root，自訂卡面也會一直保留，直到發生下列情況：

| 情況 | 是否變回原圖 |
|---|---|
| 重開機、Wallet 更新 | 否 |
| 手動清除 Wallet 快取或資料、系統在儲存空間不足時清理快取 | 是 |
| 發卡機構更換卡面網址、移除後重新加入卡片 | 是 |

變回原圖後，再取得一次 root，打開 App 按「全部重新套用」即可。

## 限制與已知事項

- **改不了卡片名稱**：支付卡名稱雖然以明文存在 GMS 的 `pay` / `android_pay` 資料庫，但 GMS 一啟動就會從伺服器同步並覆寫。票證（Valuable）的內容則有加密。目前只能換圖。
- 卡面只有在快取裡才能替換，所以要先在 Wallet 裡看過那張卡。
- 發卡機構換了卡面網址後，快取檔名會跟著改變。模組會盡量從卡片紀錄找回對應關係，但不保證每種卡都辨識得到。辨識不到時，可以勾選「顯示所有快取圖片」手動挑選。
- 只在一台小米手機（Android 16、KernelSU）上測試過，卡片類型包括 iPASS 一卡通和支付卡。其他機型和卡片類型歡迎回報。
- 只支援主要使用者（user 0）。

## 免責聲明

本專案與 Google 無任何關聯。Google 錢包官方不支援已 root 的裝置。本模組只修改本機圖片快取的顯示內容，不改動卡片、付款資料或任何伺服器資料。使用風險請自行承擔。

---

## English

**gwallet-cardart** is a KernelSU/Magisk module that swaps Google Wallet card art without hooking any app.

**How it works:** Google Wallet loads card art with Glide. The disk cache file name is `sha256(card art URL)`, and Wallet never re-downloads while the cache entry exists. The module:
1. Finds card art URLs in Wallet's card records and GMS's `pay` database.
2. Backs up the original image, then overwrites the cache file in place, which keeps the owner, mode and SELinux label.
3. Uses `inotifyd` to re-apply the custom image whenever Glide rewrites the entry.

The custom art also shows on the tap-to-pay screen.

**Usage:** Install the zip, reboot, open Wallet once so the art gets cached, then use the module's WebUI to pick an image for each card, toggle it, or restore the original. Uninstalling restores all originals.

**Temporary root?** Use the one-shot app (`gwallet-cardart-app-*.apk`). Grant it su while you have root, then apply once. The cache survives reboots, so the art stays even after root is gone, until the cache is cleared or the card art URL changes.

**Limitations:** Card names can't be changed this way. GMS re-syncs them from the server right away, and pass contents are encrypted. Tested on one Xiaomi device running KernelSU.

Not affiliated with Google. Use at your own risk.

## License

[MIT](LICENSE)
