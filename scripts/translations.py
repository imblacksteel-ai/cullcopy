# 翻訳表: 日本語（キー） → 英語・韓国語・中国語（簡体字）・中国語（繁体字）
# 使い方: python3 scripts/translations.py  … Resources/Localization/Localizable.xcstrings に書き込む
# キーはソースコード中の日本語そのもの（%lld = 整数、%@ = 文字列）

import json
import os
import sys

T = {
    "%@\n形式: %@": ("%@\nFormat: %@", "%@\n형식: %@", "%@\n格式：%@", "%@\n格式：%@"),
    "%@　%@": ("%@  %@", "%@  %@", "%@  %@", "%@  %@"),
    "%@　→　%@": ("%@  →  %@", "%@  →  %@", "%@  →  %@", "%@  →  %@"),
    "%@（%@ バイト）": ("%@ (%@ bytes)", "%@ (%@바이트)", "%@（%@ 字节）", "%@（%@ 位元組）"),
    "%@（%@）": ("%@ (%@)", "%@ (%@)", "%@（%@）", "%@（%@）"),
    "%lld": ("%lld", "%lld", "%lld", "%lld"),
    "%lld / %lld": ("%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld"),
    "%lld / %lld 件（全 %lld ファイル中、サイズが同じもの）": (
        "%lld / %lld (files with matching sizes, out of %lld)",
        "%lld / %lld개 (전체 %lld개 파일 중 크기가 같은 파일)",
        "%lld / %lld 个（共 %lld 个文件中大小相同的文件）",
        "%lld / %lld 個（共 %lld 個檔案中大小相同的檔案）"),
    "%lld / %lld 件（残り %lld 件）　%@": (
        "%lld / %lld (%lld left)  %@",
        "%lld / %lld개 (남은 %lld개)  %@",
        "%lld / %lld 个（剩余 %lld 个）  %@",
        "%lld / %lld 個（剩餘 %lld 個）  %@"),
    "%lld ファイル": ("%lld files", "파일 %lld개", "%lld 个文件", "%lld 個檔案"),
    "%lld ファイルを確認しました": ("Checked %lld files", "파일 %lld개를 확인했습니다", "已检查 %lld 个文件", "已檢查 %lld 個檔案"),
    "%lld 件コピーしたところで中断しました": (
        "Stopped after copying %lld files", "%lld개를 복사한 후 중단했습니다", "复制 %lld 个文件后已中断", "複製 %lld 個檔案後已中斷"),
    "%lld 件コピーしました": ("Copied: %lld", "%lld개를 복사했습니다", "已复制 %lld 个文件", "已複製 %lld 個檔案"),
    "%lld 個が同じ・各 %@・余分 %@": (
        "%lld identical · %@ each · %@ extra", "동일 %lld개 · 각 %@ · 여분 %@", "%lld 个相同 · 每个 %@ · 多余 %@", "%lld 個相同 · 每個 %@ · 多餘 %@"),
    "%lld 個のファイルが同じです": ("%lld identical files", "동일한 파일 %lld개", "%lld 个文件完全相同", "%lld 個檔案完全相同"),
    "%lld 組の重複が見つかりました": ("Found %lld sets of duplicates", "중복 %lld세트를 찾았습니다", "发现 %lld 组重复", "發現 %lld 組重複"),
    "%lld%%": ("%lld%%", "%lld%%", "%lld%%", "%lld%%"),
    "%lld/%lld 残り%lld": ("%lld/%lld · %lld left", "%lld/%lld · 남은 %lld", "%lld/%lld 剩余%lld", "%lld/%lld 剩餘%lld"),
    "%lld件": ("%lld", "%lld개", "%lld 个", "%lld 個"),
    "Finderで表示": ("Show in Finder", "Finder에서 보기", "在访达中显示", "在 Finder 中顯示"),
    "OK": ("OK", "확인", "好", "好"),
    "SD Importer": ("SD Importer", "SD Importer", "SD Importer", "SD Importer"),
    "SDカードが見つかりません": ("No SD card found", "SD 카드를 찾을 수 없습니다", "未找到 SD 卡", "找不到 SD 卡"),
    "SDカードの一覧を更新": ("Refresh SD card list", "SD 카드 목록 새로 고침", "刷新 SD 卡列表", "重新整理 SD 卡列表"),
    "yyyy=年  yy=年(2桁)  MM=月  dd=日　/ で区切るとサブフォルダ": (
        "yyyy=year  yy=year (2 digits)  MM=month  dd=day   Use / to create subfolders",
        "yyyy=연도  yy=연도(2자리)  MM=월  dd=일   /로 구분하면 하위 폴더",
        "yyyy=年  yy=年（2位）  MM=月  dd=日   用 / 分隔可创建子文件夹",
        "yyyy=年  yy=年（2位）  MM=月  dd=日   用 / 分隔可建立子資料夾"),
    "—": ("—", "—", "—", "—"),
    "、": (", ", ", ", "、", "、"),
    "、取り込み済み %lld 件をスキップ": (
        ", skipped %lld already imported", ", 이미 가져온 %lld개 건너뜀", "，跳过 %lld 个已导入的文件", "，略過 %lld 個已匯入的檔案"),
    "、失敗 %lld 件": (", failed: %lld", ", 실패 %lld개", "，失败 %lld 个", "，失敗 %lld 個"),
    "。読めなかったファイル %lld 件": (". Unreadable files: %lld", ". 읽을 수 없는 파일 %lld개", "。无法读取的文件 %lld 个", "。無法讀取的檔案 %lld 個"),
    "「%@」をゴミ箱に入れます。\n直前に、残るファイルと中身が同じことを確かめます。ゴミ箱から元に戻せます。": (
        "“%@” will be moved to the Trash.\nRight before that, the app confirms it is identical to the file that remains. You can restore it from the Trash.",
        "“%@”을(를) 휴지통으로 이동합니다.\n이동 직전에 남는 파일과 내용이 같은지 확인합니다. 휴지통에서 복원할 수 있습니다.",
        "将把“%@”移到废纸篓。\n移动前会确认它与保留的文件内容相同。可从废纸篓恢复。",
        "將把「%@」移到垃圾桶。\n移動前會確認它與保留的檔案內容相同。可從垃圾桶復原。"),
    "ここに保存": ("Save Here", "여기에 저장", "存储到这里", "儲存到這裡"),
    "このフォルダはチェックしたことがあります": (
        "This folder has been checked before", "이 폴더는 이전에 검사한 적이 있습니다", "此文件夹之前检查过", "此資料夾之前檢查過"),
    "このフォルダを調べる": ("Check This Folder", "이 폴더 검사", "检查此文件夹", "檢查此資料夾"),
    "やめる": ("Cancel", "취소", "取消", "取消"),
    "よく使う形式": ("Presets", "자주 쓰는 형식", "常用格式", "常用格式"),
    "ウィンドウを開く": ("Open Window", "창 열기", "打开窗口", "打開視窗"),
    "エラーが発生しました": ("An error occurred", "오류가 발생했습니다", "发生错误", "發生錯誤"),
    "キャンセル": ("Cancel", "취소", "取消", "取消"),
    "キャンセルしました": ("Cancelled", "취소했습니다", "已取消", "已取消"),
    "クリックで並べて比較": ("Click to compare side by side", "클릭하여 나란히 비교", "点按以并排比较", "按一下以並排比較"),
    "コピーが完了しました": ("Copy complete", "복사가 완료되었습니다", "复制完成", "複製完成"),
    "コピーが完了しました（一部失敗）": ("Copy complete (some failed)", "복사가 완료되었습니다 (일부 실패)", "复制完成（部分失败）", "複製完成（部分失敗）"),
    "コピーが終わっているファイルは残ります。次に「開始」を押すと続きからコピーできます。": (
        "Files already copied will be kept. Press Start next time to continue where you left off.",
        "복사가 끝난 파일은 남아 있습니다. 다음에 '시작'을 누르면 이어서 복사할 수 있습니다.",
        "已复制的文件会保留。下次按“开始”即可从中断处继续复制。",
        "已複製的檔案會保留。下次按「開始」即可從中斷處繼續複製。"),
    "コピーしたファイルは消えません。履歴の記録だけを消去します。": (
        "Copied files will not be deleted. Only the history records are cleared.",
        "복사한 파일은 삭제되지 않습니다. 기록만 지웁니다.",
        "已复制的文件不会被删除，只清除历史记录。",
        "已複製的檔案不會被刪除，只清除歷史記錄。"),
    "コピーするファイルはありませんでした": ("Nothing to copy", "복사할 파일이 없습니다", "没有需要复制的文件", "沒有需要複製的檔案"),
    "コピーを中断しました": ("Copy stopped", "복사를 중단했습니다", "已中断复制", "已中斷複製"),
    "コピーを実行すると、ここに記録されます。": ("Imports will be recorded here.", "복사를 실행하면 여기에 기록됩니다.", "执行复制后会记录在这里。", "執行複製後會記錄在這裡。"),
    "コピー中": ("Copying", "복사 중", "正在复制", "正在複製"),
    "コピー中です。終了しますか？": ("A copy is in progress. Quit anyway?", "복사 중입니다. 종료하시겠습니까?", "正在复制。要退出吗？", "正在複製。要結束嗎？"),
    "コピー中：%lld / %lld 件（残り %lld 件）": (
        "Copying: %lld / %lld (%lld left)", "복사 중: %lld / %lld개 (남은 %lld개)", "正在复制：%lld / %lld 个（剩余 %lld 个）", "正在複製：%lld / %lld 個（剩餘 %lld 個）"),
    "コピー元": ("Source", "원본", "来源", "來源"),
    "コピー元から %lld 件を削除": ("Deleted %lld from the source", "원본에서 %lld개 삭제", "已从来源删除 %lld 个", "已從來源刪除 %lld 個"),
    "コピー元から %lld 件を削除しました": ("Deleted %lld files from the source", "원본에서 %lld개를 삭제했습니다", "已从来源删除 %lld 个文件", "已從來源刪除 %lld 個檔案"),
    "コピー元から %lld 件を削除しました（削除できなかったもの %lld 件）": (
        "Deleted %lld files from the source (%lld could not be deleted)",
        "원본에서 %lld개를 삭제했습니다 (삭제하지 못한 파일 %lld개)",
        "已从来源删除 %lld 个文件（%lld 个无法删除）",
        "已從來源刪除 %lld 個檔案（%lld 個無法刪除）"),
    "コピー元とコピー先の中身が一致しません": (
        "The source and the copy do not match", "원본과 복사본의 내용이 일치하지 않습니다", "来源与副本的内容不一致", "來源與副本的內容不一致"),
    "コピー元にする": ("Use as Source", "원본으로 사용", "用作来源", "用作來源"),
    "コピー元の写真・動画を探しています": ("Looking for photos and videos in the source", "원본에서 사진·동영상을 찾는 중", "正在来源中查找照片和视频", "正在來源中尋找照片和影片"),
    "コピー元はそのまま残しました": ("The source files were kept", "원본 파일을 그대로 남겼습니다", "已保留来源文件", "已保留來源檔案"),
    "コピー元を削除せずに残しました": ("The source files were kept without deleting", "원본을 삭제하지 않고 남겼습니다", "未删除来源文件，已保留", "未刪除來源檔案，已保留"),
    "コピー元を削除中…": ("Deleting source files…", "원본 삭제 중…", "正在删除来源文件…", "正在刪除來源檔案…"),
    "コピー元フォルダを削除しますか？": ("Delete the source files?", "원본 폴더를 삭제하시겠습니까?", "要删除来源文件吗？", "要刪除來源檔案嗎？"),
    "コピー先": ("Destination", "저장 위치", "目标位置", "目標位置"),
    "コピー先にあることを確認できた %lld 件の写真・動画をSDカードから削除します。フォルダ構成（DCIM など）は残します。": (
        "Delete %lld photos and videos from the SD card that were confirmed at the destination. The folder structure (such as DCIM) is kept.",
        "저장 위치에 있는 것이 확인된 사진·동영상 %lld개를 SD 카드에서 삭제합니다. 폴더 구조(DCIM 등)는 남겨 둡니다.",
        "将从 SD 卡删除已在目标位置确认存在的 %lld 个照片和视频。文件夹结构（如 DCIM）会保留。",
        "將從 SD 卡刪除已在目標位置確認存在的 %lld 個照片和影片。資料夾結構（如 DCIM）會保留。"),
    "コピー先にあることを確認できた %lld 件の写真・動画を削除し、空になったフォルダも削除します。": (
        "Delete %lld photos and videos that were confirmed at the destination, along with any folders left empty.",
        "저장 위치에 있는 것이 확인된 사진·동영상 %lld개를 삭제하고, 비게 된 폴더도 삭제합니다.",
        "将删除已在目标位置确认存在的 %lld 个照片和视频，并删除变空的文件夹。",
        "將刪除已在目標位置確認存在的 %lld 個照片和影片，並刪除變空的資料夾。"),
    "コピー先をFinderで開く": ("Open the destination in Finder", "저장 위치를 Finder에서 열기", "在访达中打开目标位置", "在 Finder 中打開目標位置"),
    "コピー先を開く": ("Open Destination", "저장 위치 열기", "打开目标位置", "打開目標位置"),
    "コピー後のサイズが一致しません（元: %lld / コピー: %lld）": (
        "Size mismatch after copying (source: %lld / copy: %lld)", "복사 후 크기가 일치하지 않습니다 (원본: %lld / 복사본: %lld)",
        "复制后大小不一致（来源：%lld / 副本：%lld）", "複製後大小不一致（來源：%lld / 副本：%lld）"),
    "ゴミ箱": ("Trashed", "휴지통", "废纸篓", "垃圾桶"),
    "ゴミ箱には入らず、元に戻せません。": (
        "Files are not moved to the Trash and cannot be restored.", "휴지통으로 이동하지 않으며 복원할 수 없습니다.", "文件不会移到废纸篓，无法恢复。", "檔案不會移到垃圾桶，無法復原。"),
    "ゴミ箱に入れますか？": ("Move to Trash?", "휴지통으로 이동하시겠습니까?", "要移到废纸篓吗？", "要移到垃圾桶嗎？"),
    "ゴミ箱に入れられませんでした": ("Could not move to Trash", "휴지통으로 이동할 수 없습니다", "无法移到废纸篓", "無法移到垃圾桶"),
    "ゴミ箱に入れられませんでした：%@": ("Could not move to Trash: %@", "휴지통으로 이동할 수 없습니다: %@", "无法移到废纸篓：%@", "無法移到垃圾桶：%@"),
    "ゴミ箱に入れる": ("Move to Trash", "휴지통으로 이동", "移到废纸篓", "移到垃圾桶"),
    "サイズ": ("Size", "크기", "大小", "大小"),
    "スキップ": ("Skipped", "건너뜀", "跳过", "略過"),
    "チェックを実行すると、ここに記録されます。": ("Checks will be recorded here.", "검사를 실행하면 여기에 기록됩니다.", "执行检查后会记录在这里。", "執行檢查後會記錄在這裡。"),
    "チェック履歴": ("Check History", "검사 기록", "检查历史", "檢查歷史"),
    "チェック履歴をすべて消去しますか？": ("Clear all check history?", "검사 기록을 모두 지우시겠습니까?", "要清除所有检查历史吗？", "要清除所有檢查歷史嗎？"),
    "パスをコピー": ("Copy Path", "경로 복사", "拷贝路径", "拷貝路徑"),
    "ファイルには影響しません。履歴の記録だけを消去します。": (
        "Your files are not affected. Only the history records are cleared.", "파일에는 영향이 없습니다. 기록만 지웁니다.", "不会影响文件，只清除历史记录。", "不會影響檔案，只清除歷史記錄。"),
    "ファイルを数えています…": ("Counting files…", "파일을 세는 중…", "正在统计文件…", "正在統計檔案…"),
    "ファイルを数えています… %lld 件": ("Counting files… %lld", "파일을 세는 중… %lld개", "正在统计文件… %lld 个", "正在統計檔案… %lld 個"),
    "ファイルを確認中…": ("Checking files…", "파일 확인 중…", "正在检查文件…", "正在檢查檔案…"),
    "フォルダ": ("Folder", "폴더", "文件夹", "資料夾"),
    "フォルダ…": ("Folder…", "폴더…", "文件夹…", "資料夾…"),
    "フォルダを選んで「重複チェック開始」を押してください。": (
        "Choose a folder and press Start Duplicate Check.", "폴더를 선택하고 '중복 검사 시작'을 누르세요.", "请选择文件夹并按“开始检查重复”。", "請選擇資料夾並按「開始檢查重複」。"),
    "フォルダ分けしない": ("No Subfolders", "폴더 나누지 않음", "不分文件夹", "不分資料夾"),
    "フォルダ名": ("Folder Name", "폴더 이름", "文件夹名称", "資料夾名稱"),
    "一番古い": ("Oldest", "가장 오래됨", "最旧", "最舊"),
    "一部失敗": ("Partial", "일부 실패", "部分失败", "部分失敗"),
    "並べて比較": ("Compare", "나란히 비교", "并排比较", "並排比較"),
    "中断": ("Stopped", "중단", "已中断", "已中斷"),
    "中身が完全に同じファイルを、サブフォルダまで含めて探します。隠しファイル・0バイトのファイル・写真ライブラリなどのパッケージの中身は対象外です。ファイルの削除や移動はしません。": (
        "Finds files with exactly the same content, including subfolders. Hidden files, empty files, and the contents of packages such as Photos libraries are skipped. Files are never deleted or moved automatically.",
        "하위 폴더까지 포함해 내용이 완전히 같은 파일을 찾습니다. 숨김 파일, 0바이트 파일, 사진 보관함 같은 패키지 내부는 제외됩니다. 파일을 자동으로 삭제하거나 이동하지 않습니다.",
        "查找内容完全相同的文件（包括子文件夹）。隐藏文件、0 字节文件以及照片图库等包的内容不在检查范围内。不会自动删除或移动文件。",
        "尋找內容完全相同的檔案（包括子資料夾）。隱藏檔案、0 位元組檔案以及照片圖庫等套件的內容不在檢查範圍內。不會自動刪除或移動檔案。"),
    "中身は完全に一致しています（各 %@）。違うのは名前・場所・日付だけです。": (
        "The contents are exactly the same (%@ each). Only the names, locations, and dates differ.",
        "내용이 완전히 같습니다 (각 %@). 다른 것은 이름·위치·날짜뿐입니다.",
        "内容完全相同（每个 %@）。只有名称、位置和日期不同。",
        "內容完全相同（每個 %@）。只有名稱、位置和日期不同。"),
    "中身を比較中": ("Comparing contents", "내용 비교 중", "正在比较内容", "正在比較內容"),
    "中身を比較中：%lld / %lld 件（残り %lld 件）": (
        "Comparing: %lld / %lld (%lld left)", "내용 비교 중: %lld / %lld개 (남은 %lld개)", "正在比较：%lld / %lld 个（剩余 %lld 个）", "正在比較：%lld / %lld 個（剩餘 %lld 個）"),
    "中身を照合してから削除しています": ("Verifying contents before deleting", "내용을 대조한 후 삭제하는 중", "正在核对内容后删除", "正在核對內容後刪除"),
    "余分": ("Extra", "여분", "多余", "多餘"),
    "余分なファイル %lld 個・余分な容量 %@（%lld ファイルを確認）": (
        "Extra files: %lld · Extra space: %@ (%lld files checked)",
        "여분 파일 %lld개 · 여분 용량 %@ (파일 %lld개 확인)",
        "多余文件 %lld 个 · 多余空间 %@（已检查 %lld 个文件）",
        "多餘檔案 %lld 個 · 多餘空間 %@（已檢查 %lld 個檔案）"),
    "余分な容量": ("Extra Space", "여분 용량", "多余空间", "多餘空間"),
    "作成日": ("Created", "생성일", "创建日期", "建立日期"),
    "保存例": ("Example", "저장 예시", "保存示例", "儲存範例"),
    "元ファイル": ("Source Files", "원본 파일", "来源文件", "來源檔案"),
    "再チェックする": ("Check Again", "다시 검사", "重新检查", "重新檢查"),
    "写真・動画が見つかりませんでした": ("No photos or videos found", "사진·동영상을 찾지 못했습니다", "未找到照片或视频", "找不到照片或影片"),
    "削除 %lld": ("Deleted %lld", "삭제 %lld", "已删除 %lld", "已刪除 %lld"),
    "削除 %lld・失敗 %lld": ("Deleted %lld · Failed %lld", "삭제 %lld · 실패 %lld", "已删除 %lld · 失败 %lld", "已刪除 %lld · 失敗 %lld"),
    "削除/残した": ("Deleted/Kept", "삭제/보관", "删除/保留", "刪除/保留"),
    "削除する": ("Delete", "삭제", "删除", "刪除"),
    "削除するか選ばないまま次の操作に進みました": (
        "Moved on without choosing whether to delete", "삭제 여부를 선택하지 않고 다음 작업으로 넘어갔습니다", "未选择是否删除就进行了下一步操作", "未選擇是否刪除就進行了下一步操作"),
    "削除の確認は表示されませんでした": ("No delete prompt was shown", "삭제 확인이 표시되지 않았습니다", "未显示删除确认", "未顯示刪除確認"),
    "前の重複": ("Previous", "이전 중복", "上一组", "上一組"),
    "前回のチェック": ("Last Check", "지난 검사", "上次检查", "上次檢查"),
    "前回：%@\n結果：%@\n\nもう一度チェックしますか？": (
        "Last check: %@\nResult: %@\n\nCheck again?", "지난 검사: %@\n결과: %@\n\n다시 검사하시겠습니까?", "上次：%@\n结果：%@\n\n要再检查一次吗？", "上次：%@\n結果：%@\n\n要再檢查一次嗎？"),
    "取り込み": ("Import", "가져오기", "导入", "匯入"),
    "取り込みのコピー先": ("Import Destination", "가져오기 저장 위치", "导入目标位置", "匯入目標位置"),
    "取り込みをキャンセル": ("Cancel Import", "가져오기 취소", "取消导入", "取消匯入"),
    "取り込み履歴": ("Import History", "가져오기 기록", "导入历史", "匯入歷史"),
    "取り込み開始": ("Start Import", "가져오기 시작", "开始导入", "開始匯入"),
    "同じファイルはありませんでした": ("No duplicates found", "중복 파일이 없습니다", "没有重复文件", "沒有重複檔案"),
    "同じ中身のファイルが他に見つからないため、ゴミ箱に入れませんでした。": (
        "Not moved to the Trash because no other file with the same content was found.",
        "같은 내용의 다른 파일을 찾을 수 없어 휴지통으로 이동하지 않았습니다.",
        "未找到其他内容相同的文件，因此未移到废纸篓。",
        "找不到其他內容相同的檔案，因此未移到垃圾桶。"),
    "場所": ("Location", "위치", "位置", "位置"),
    "変更…": ("Change…", "변경…", "更改…", "更改…"),
    "変更日": ("Modified", "수정일", "修改日期", "修改日期"),
    "完了": ("Done", "완료", "完成", "完成"),
    "対象": ("To Copy", "대상", "目标", "目標"),
    "対象＝今回コピーしようとした数　スキップ＝取り込み済み　残り＝失敗・中断でコピーできなかった数　元ファイル＝コピー元を削除したか残したか": (
        "To Copy = files to copy this time   Skipped = already imported   Left = not copied due to failure or stop   Source Files = deleted or kept",
        "대상 = 이번에 복사하려던 수   건너뜀 = 이미 가져온 파일   남음 = 실패·중단으로 복사하지 못한 수   원본 파일 = 원본을 삭제했는지 남겼는지",
        "目标 = 本次要复制的数量   跳过 = 已导入   剩余 = 因失败或中断未能复制的数量   来源文件 = 是否删除或保留了来源",
        "目標 = 本次要複製的數量   略過 = 已匯入   剩餘 = 因失敗或中斷未能複製的數量   來源檔案 = 是否刪除或保留了來源"),
    "履歴はまだありません": ("No history yet", "아직 기록이 없습니다", "暂无历史记录", "尚無歷史記錄"),
    "履歴をすべて消去しますか？": ("Clear all import history?", "기록을 모두 지우시겠습니까?", "要清除所有历史记录吗？", "要清除所有歷史記錄嗎？"),
    "履歴を消去…": ("Clear History…", "기록 지우기…", "清除历史…", "清除歷史…"),
    "履歴ファイルを表示": ("Show History File", "기록 파일 보기", "显示历史文件", "顯示歷史檔案"),
    "待機中": ("Idle", "대기 중", "空闲", "閒置"),
    "成功": ("Copied", "성공", "成功", "成功"),
    "新しいファイルはありません（取り込み済み %lld 件）": (
        "No new files (%lld already imported)", "새 파일이 없습니다 (이미 가져온 파일 %lld개)", "没有新文件（已导入 %lld 个）", "沒有新檔案（已匯入 %lld 個）"),
    "新規なし": ("No New", "새 파일 없음", "无新文件", "無新檔案"),
    "日時": ("Date", "날짜", "日期", "日期"),
    "未選択": ("Not chosen", "선택 안 함", "未选择", "未選擇"),
    "検索中…": ("Searching…", "검색 중…", "正在搜索…", "正在搜尋…"),
    "次の重複": ("Next", "다음 중복", "下一组", "下一組"),
    "残した": ("Kept", "보관함", "已保留", "已保留"),
    "残す": ("Keep", "보관", "保留", "保留"),
    "残り": ("Left", "남음", "剩余", "剩餘"),
    "残るファイル（%@）と中身が一致しなくなっていたため、ゴミ箱に入れませんでした。もう一度チェックしてください。": (
        "Not moved to the Trash because it no longer matches the remaining file (%@). Please check again.",
        "남는 파일(%@)과 내용이 더 이상 일치하지 않아 휴지통으로 이동하지 않았습니다. 다시 검사하세요.",
        "由于与保留的文件（%@）内容已不一致，未移到废纸篓。请重新检查。",
        "由於與保留的檔案（%@）內容已不一致，未移到垃圾桶。請重新檢查。"),
    "比較する重複はもうありません。": ("There are no more duplicates to compare.", "비교할 중복이 더 이상 없습니다.", "没有更多需要比较的重复项。", "沒有更多需要比較的重複項。"),
    "消去する": ("Clear", "지우기", "清除", "清除"),
    "状態": ("Status", "상태", "状态", "狀態"),
    "確認してゴミ箱へ移動中…": ("Verifying and moving to Trash…", "확인 후 휴지통으로 이동 중…", "正在确认并移到废纸篓…", "正在確認並移到垃圾桶…"),
    "確認数": ("Checked", "확인 수", "检查数", "檢查數"),
    "種類": ("Kind", "종류", "种类", "種類"),
    "空欄ならフォルダ分けしない": ("Leave empty for no subfolders", "비워 두면 폴더를 나누지 않음", "留空则不分文件夹", "留空則不分資料夾"),
    "終了": ("Quit", "종료", "退出", "結束"),
    "終了しない": ("Don’t Quit", "종료 안 함", "不退出", "不結束"),
    "終了する": ("Quit", "종료", "退出", "結束"),
    "結果はまだありません": ("No results yet", "아직 결과가 없습니다", "暂无结果", "尚無結果"),
    "読めず": ("Unreadable", "읽기 불가", "无法读取", "無法讀取"),
    "調べるフォルダ": ("Folder to Check", "검사할 폴더", "要检查的文件夹", "要檢查的資料夾"),
    "途中で中断": ("Stopped partway", "도중에 중단", "中途中断", "中途中斷"),
    "選択…": ("Choose…", "선택…", "选择…", "選擇…"),
    "選択内容": ("Selection", "선택 내용", "所选内容", "所選內容"),
    "重複 %lld 組・余分なファイル %lld 個・余分な容量 %@": (
        "%lld duplicate sets · Extra files: %lld · Extra space: %@", "중복 %lld세트 · 여분 파일 %lld개 · 여분 용량 %@",
        "重复 %lld 组 · 多余文件 %lld 个 · 多余空间 %@", "重複 %lld 組 · 多餘檔案 %lld 個 · 多餘空間 %@"),
    "重複(組)": ("Sets", "중복(세트)", "重复（组）", "重複（組）"),
    "重複なし（%lld ファイルを確認）": ("No duplicates (%lld files checked)", "중복 없음 (파일 %lld개 확인)", "无重复（已检查 %lld 个文件）", "無重複（已檢查 %lld 個檔案）"),
    "重複はありません": ("No duplicates", "중복이 없습니다", "没有重复", "沒有重複"),
    "重複はすべて片付きました": ("All duplicates are cleared", "중복을 모두 정리했습니다", "所有重复项都已处理", "所有重複項都已處理"),
    "重複チェック": ("Duplicates", "중복 검사", "重复检查", "重複檢查"),
    "重複チェックをキャンセル": ("Cancel Duplicate Check", "중복 검사 취소", "取消重复检查", "取消重複檢查"),
    "重複チェック開始": ("Start Duplicate Check", "중복 검사 시작", "开始检查重复", "開始檢查重複"),
    "SD Importer は無料で使えます。気に入っていただけたら、チップで応援してもらえるとうれしいです。": (
        "SD Importer is free to use. If you like it, a tip would mean a lot.",
        "SD Importer는 무료로 사용할 수 있습니다. 마음에 드셨다면 팁으로 응원해 주시면 기쁘겠습니다.",
        "SD Importer 可免费使用。如果喜欢，欢迎用小费支持我们。",
        "SD Importer 可免費使用。如果喜歡，歡迎用小費支持我們。"),
    "「%@」を調べる許可が必要です。フォルダを選んで「許可」を押してください。": (
        "Permission is needed to check \u201c%@\u201d. Select the folder and click Allow.",
        "\u201c%@\u201d을(를) 검사하려면 허용이 필요합니다. 폴더를 선택하고 '허용'을 누르세요.",
        "需要权限才能检查“%@”。请选择该文件夹并点按“允许”。",
        "需要權限才能檢查「%@」。請選擇該資料夾並按「允許」。"),
    "「%@」を選んだまま「許可」を押してください。次回からは聞かれません。": (
        "With \u201c%@\u201d selected, click Allow. You won\u2019t be asked again.",
        "\u201c%@\u201d이(가) 선택된 상태에서 '허용'을 누르세요. 다음부터는 묻지 않습니다.",
        "保持选中“%@”并点按“允许”。以后不会再询问。",
        "保持選取「%@」並按「允許」。之後不會再詢問。"),
    "あとで": ("Later", "나중에", "以后再说", "以後再說"),
    "ありがとうございます！": ("Thank you!", "감사합니다!", "谢谢！", "謝謝！"),
    "いただいたチップは、これからの開発に使わせていただきます。": (
        "Your tip will go toward future development.", "보내주신 팁은 앞으로의 개발에 사용하겠습니다.", "您的小费将用于今后的开发。", "您的小費將用於今後的開發。"),
    "いまはチップを読み込めません。ネットワークを確認して、あとでもう一度お試しください。": (
        "Tips can\u2019t be loaded right now. Check your network and try again later.",
        "지금은 팁을 불러올 수 없습니다. 네트워크를 확인하고 나중에 다시 시도하세요.",
        "暂时无法加载小费选项。请检查网络后稍后再试。",
        "暫時無法載入小費選項。請檢查網路後稍後再試。"),
    "このSDカードを読むには、最初に許可が必要です": (
        "Permission is needed the first time to read this SD card", "이 SD 카드를 읽으려면 처음에 허용이 필요합니다",
        "首次读取此 SD 卡需要授权", "首次讀取此 SD 卡需要授權"),
    "アクセスを許可…": ("Allow Access…", "접근 허용…", "允许访问…", "允許存取…"),
    "コピー先「%@」に保存する許可が必要です。フォルダを選んで「許可」を押してください。": (
        "Permission is needed to save to \u201c%@\u201d. Select the folder and click Allow.",
        "저장 위치 \u201c%@\u201d에 저장하려면 허용이 필요합니다. 폴더를 선택하고 '허용'을 누르세요.",
        "需要权限才能保存到“%@”。请选择该文件夹并点按“允许”。",
        "需要權限才能儲存到「%@」。請選擇該資料夾並按「允許」。"),
    "許可": ("Allow", "허용", "允许", "允許"),
    "購入を確認できませんでした。": ("The purchase could not be verified.", "구매를 확인할 수 없습니다.", "无法验证购买。", "無法驗證購買。"),
    "開発を支援する": ("Support Development", "개발 후원하기", "支持开发", "支持開發"),
    "開発を支援する…": ("Support Development…", "개발 후원하기…", "支持开发…", "支持開發…"),
    "閉じる": ("Close", "닫기", "关闭", "關閉"),
    "開く": ("Open", "열기", "打开", "打開"),
    "（中身が一致しないなどで削除しなかったもの %lld 件）": (
        " (%lld not deleted, e.g. because the contents did not match)", " (내용 불일치 등으로 삭제하지 않은 파일 %lld개)",
        "（%lld 个因内容不一致等原因未删除）", "（%lld 個因內容不一致等原因未刪除）"),
    "（拡張子なし）": ("(no extension)", "(확장자 없음)", "（无扩展名）", "（無副檔名）"),
    "（調べたフォルダの直下）": ("(top of the checked folder)", "(검사한 폴더 바로 아래)", "（所检查文件夹的顶层）", "（所檢查資料夾的頂層）"),
}

LANGS = ["en", "ko", "zh-Hans", "zh-Hant"]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "Resources/Localization/Localizable.xcstrings")
    catalog = json.load(open(path, encoding="utf-8"))
    missing = []
    for key, entry in catalog["strings"].items():
        if key not in T:
            missing.append(key)
            continue
        entry["localizations"] = {
            lang: {"stringUnit": {"state": "translated", "value": value}}
            for lang, value in zip(LANGS, T[key])
        }
        # 日本語はキーそのもの。ja.lproj を作らないと、日本語の Mac でも英語（開発言語）が出てしまう
        entry["localizations"]["ja"] = {"stringUnit": {"state": "translated", "value": key}}
    unused = sorted(set(T) - set(catalog["strings"]))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    if unused:
        print("翻訳表にあるがコードにないキー:", *unused, sep="\n  ")
    if missing:
        print("翻訳が足りないキー:", *missing, sep="\n  ")
        sys.exit(1)
    print(f"{len(catalog['strings'])} 件の翻訳を書き込みました")


if __name__ == "__main__":
    main()
