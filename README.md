# 廢棄城市 FPS　Abandoned City FPS

末日廢墟中的第一人稱射擊遊戲：撐過一波波殭屍進攻，或在 12 人大逃殺中活到最後。
使用 **Godot 4.7** 開發，所有美術、音效與音樂皆由程式即時產生，不含任何外部素材檔。

## 立即下載遊玩

| 平台 | 下載 | 說明 |
|---|---|---|
| 🖥️ Windows | [Releases → `AbandonedCityFPS-windows.exe`](https://github.com/a201009200979603117-create/abandoned-city-fps/releases/latest) | 單一執行檔，下載後雙擊即可，不需安裝 |
| 📱 Android | [Releases → `AbandonedCityFPS-android-debug.apk`](https://github.com/a201009200979603117-create/abandoned-city-fps/releases/latest) | 需允許「安裝未知來源應用程式」（見下方） |

> 本遊戲不提供網頁版（瀏覽器上效能與音訊表現不穩定），請下載上方版本遊玩。想要更流暢請到「設定 → 畫質」調整。

## 遊戲特色

**殭屍關卡（10 關）**
- 一波波殭屍進攻，每波結束可選擇技能（衝擊波、戰地急救、手榴彈、寒霜領域、狂暴），滿級後還能「突破」進化
- 第 3 關起最後一波有 **Boss**（震地波、衝鋒、殘血狂暴召喚小兵）
- 多種敵人：一般、跑者、坦克、**吐酸殭屍**（遠程）、**膨脹者**（死亡爆炸）
- 場景危害：**爆炸油桶**、**毒氣區**；每關有不同的**時段與天氣**（夜晚頭燈、下雨、暴風雨閃電、濃霧、落塵）

**大逃殺（12 人，你 + 11 名 AI）**
- 開局**跳傘**，落地後撿槍；安全區逐步縮小，縮圈有警報與倒數
- 手榴彈、醫療包、護甲板；**補給箱空投**會出現在小地圖上
- AI 有視野與反應時間，會聽聲辨位、殘血找掩體、治療、丟手榴彈
- 奪冠可獲得空投裝備

**成長與收集**
- 玩家等級與經驗、19 個成就、**每日任務**
- 6 種槍枝、9 種皮膚（抽獎取得）、6 個部位的裝備、4 種槍枝配件（握把／擴容彈匣／槍口穩定器／瞄準鏡）
- 爆頭判定與傷害數字、受擊方向指示、死亡演出

## 操作

### 電腦
| 動作 | 按鍵 | 動作 | 按鍵 |
|---|---|---|---|
| 移動 | `W` `A` `S` `D` | 射擊 | 滑鼠左鍵 |
| 奔跑 | `Ctrl` | 開鏡 | 滑鼠右鍵 |
| 蹲下 | `Shift` | 換彈 | `R` |
| 跳躍 | `空白鍵` | 拾取 / 開啟 | `E` |
| 技能（殭屍關卡） | `Z` `X` `C` `V` `B` | 切換槍（大逃殺） | `1` `2` `Q` |
| 手榴彈 / 醫療包 / 護甲板（大逃殺） | `G` / `H` / `T` | 暫停 | `Esc` |

### 手機（觸控）
- 左下搖桿移動（推到底往前＝自動奔跑）；其餘空白處拖曳轉動視角
- 右下大按鈕射擊，另有跳躍、蹲下、開鏡、換彈、拾取；左側另有一顆左手射擊鍵
- 大逃殺：下方武器欄點選切槍；手榴彈、醫療包、護甲板在右下
- 殭屍關卡：點左上技能列施放技能
- 設定中可調整**按鍵大小、透明度、位置（拖曳編輯）**、**左手模式**與**陀螺儀瞄準**
- Android 返回鍵＝暫停 / 返回上一頁

## 安裝 APK（Android）
1. 用手機瀏覽器打開 [Releases](https://github.com/a201009200979603117-create/abandoned-city-fps/releases/latest)，下載 `AbandonedCityFPS-android-debug.apk`
2. 開啟下載的檔案；若系統提示，請允許該瀏覽器或檔案管理員「安裝未知來源應用程式」
3. 安裝後從桌面開啟即可。APK 為 debug 簽章，Play 保護機制可能跳出提示，選擇「仍要安裝」

## 效能與疑難排解
- **畫面卡頓**：設定 → 畫質改為「低」（降低解析度、關閉陰影與動態模糊）。手機預設為「中」；開局若平均幀率過低會自動降一級
- **Windows 出現 SmartScreen 警告**：檔案未經程式碼簽署，選「其他資訊 → 仍要執行」
- **存檔位置**：Windows 為 `%APPDATA%\Godot\app_userdata\AbandonedCityFPS\profile.cfg`；Android 存在應用程式私有儲存空間（解除安裝會一併清除存檔）
- **清除存檔**：設定頁最下方「清除所有存檔資料」

## 從原始碼執行與匯出
需求：[Godot 4.7.2](https://godotengine.org/)（Mobile 渲染器）

```bash
git clone https://github.com/a201009200979603117-create/abandoned-city-fps.git
cd abandoned-city-fps
godot --path .                       # 直接執行
godot --headless --path . --export-release "Windows Desktop" build/AbandonedCityFPS.exe
godot --headless --path . --export-debug   "Android" build/AbandonedCityFPS.apk
```
匯出需先安裝對應的匯出範本；Android 需設定 Java 17 與 Android SDK（`export_presets.cfg` 內已有預設）。

### 自動測試
```bash
# 無頭冒煙測試（殭屍關卡第 N 關 / 大逃殺）：AI 與敵人自動對戰到結算
T_MODE=zombie T_LEVEL=3 godot --headless --path . -s tests/smoke.gd
T_MODE=br                godot --headless --path . -s tests/smoke.gd
godot --headless --path . -s tests/shoot_check.gd            # 射擊特效物件池是否洩漏
T_MODE=br godot --path . -s tests/touch_check.gd             # 模擬手機觸控操作
T_MODE=br T_SECS=120 godot --path . -s tests/mem_check.gd    # 記憶體 / 物件數趨勢
```
設定環境變數 `AC_SAVE=<路徑>` 可讓測試使用獨立存檔，不會動到你的真實進度。

## 專案結構
```
autoload/   全域單例：Save（存檔）、Game（狀態/成就/任務）、Sfx（音效與音樂合成）
scenes/     玩家、武器、敵人、道具場景
scripts/    br/（大逃殺）  enemies/  systems/（關卡、天氣、特效）  data/（武器、技能、關卡、成長資料）
ui/         HUD、選單、觸控操作、小地圖、動態模糊
shaders/    建築、地面、動態模糊著色器
tests/      自動測試
```

## 致謝
- 字型：[Noto Sans TC](https://fonts.google.com/noto/specimen/Noto+Sans+TC)（SIL Open Font License，見 `ui/NotoSansTC-OFL.txt`）
- 引擎：[Godot Engine](https://godotengine.org/)（MIT）
