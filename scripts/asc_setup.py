#!/usr/bin/env python3
"""App Store Connect の掲載情報を API で登録する（何度実行しても同じ結果になる）

    python3 scripts/asc_setup.py metadata      # バージョン番号・カテゴリ・年齢制限・5言語の掲載文
    python3 scripts/asc_setup.py screenshots   # build/screenshots のスクリーンショットをアップロード
    python3 scripts/asc_setup.py review        # 審査メモ（連絡先は画面で入力）
    python3 scripts/asc_setup.py build         # 処理が終わった最新のビルドを、提出するバージョンに付ける
    python3 scripts/asc_setup.py pricing       # 価格（無料）と販売地域（すべての国と地域）
    python3 scripts/asc_setup.py tips          # チップ（消耗型のアプリ内課金）3つ：名前・説明・価格・販売地域・審査用画像

API キーはキーチェーンから読む（scripts/asc_token.swift）。値は画面に出さない。
掲載文は AppStore/metadata/<言語>/*.txt（release_notes.txt は「このバージョンの新機能」）。
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.imblacksteelai.sdimporter"
VERSION = "1.1.0"
COPYRIGHT = "2026 Ryo"
LOCALES = ["ja", "en-US", "ko", "zh-Hans", "zh-Hant"]
SCREENSHOT_LANG = {"ja": "ja", "en-US": "en", "ko": "ko", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant"}

_token = None


def token():
    global _token
    if _token is None:
        _token = subprocess.run(["swift", os.path.join(ROOT, "scripts/asc_token.swift")],
                                check=True, capture_output=True, text=True).stdout.strip()
    return _token


def call(method, path, body=None, query=None):
    url = API + path
    if query:
        url += "?" + "&".join(f"{k}={urllib.request.quote(str(v))}" for k, v in query.items())
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{x.get('code')}: {x.get('detail') or x.get('title')}" for x in errors)
        except ValueError:
            pass
        raise SystemExit(f"API エラー {e.code} {method} {path}\n  {detail}")


def meta(locale, name):
    path = os.path.join(ROOT, "AppStore/metadata", locale, f"{name}.txt")
    with open(path, encoding="utf-8") as f:
        return f.read().strip()


def find_app():
    apps = call("GET", "/v1/apps", query={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        raise SystemExit("App Store Connect にアプリがありません。先に作成してください（docs/appstore.md）。")
    return apps[0]["id"]


def editable_version(app_id, create=False):
    versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions", query={"filter[platform]": "MAC_OS"})["data"]
    for v in versions:
        if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            return v
    if create:
        v = call("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "MAC_OS", "versionString": VERSION, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"バージョン {VERSION} を作成しました")
        return v
    raise SystemExit("編集できるバージョンがありません。先に metadata を実行してください。")


def editable_app_info(app_id):
    infos = call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    for info in infos:
        if info["attributes"].get("appStoreState") != "READY_FOR_SALE" and info["attributes"].get("state") != "READY_FOR_DISTRIBUTION":
            return info
    return infos[0]


# --- 掲載情報 -------------------------------------------------------------------

def setup_metadata():
    app_id = find_app()
    version = editable_version(app_id, create=True)
    call("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"],
        "attributes": {"versionString": VERSION, "copyright": COPYRIGHT}}})
    print(f"バージョン: {VERSION}（著作権表示 {COPYRIGHT}）")

    # コンテンツの配信権：第三者のコンテンツ（音楽・映像など）を含まない
    call("PATCH", f"/v1/apps/{app_id}", {"data": {
        "type": "apps", "id": app_id, "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    print("コンテンツの配信権: 第三者のコンテンツは使用していない")

    info = editable_app_info(app_id)
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {
        "type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": "PHOTO_AND_VIDEO"}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}}}}})
    print("カテゴリ: 写真／ビデオ（サブ：仕事効率化）")

    setup_age_rating(info["id"])

    # 名前・サブタイトル・プライバシーポリシー URL（App 情報の言語ごとの項目）
    existing = {x["attributes"]["locale"]: x for x in
                call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]}
    for locale in LOCALES:
        attrs = {"name": meta(locale, "name"), "subtitle": meta(locale, "subtitle"),
                 "privacyPolicyUrl": meta(locale, "privacy_url")}
        if locale in existing:
            call("PATCH", f"/v1/appInfoLocalizations/{existing[locale]['id']}", {"data": {
                "type": "appInfoLocalizations", "id": existing[locale]["id"], "attributes": attrs}})
        else:
            call("POST", "/v1/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations", "attributes": {"locale": locale, **attrs},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
    print("名前・サブタイトル・プライバシーポリシー URL: " + ", ".join(LOCALES))

    # 説明・キーワード・宣伝文・URL（バージョンの言語ごとの項目）
    existing = {x["attributes"]["locale"]: x for x in
                call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}
    for locale in LOCALES:
        attrs = {"description": meta(locale, "description"), "keywords": meta(locale, "keywords"),
                 "promotionalText": meta(locale, "promotional_text"), "supportUrl": meta(locale, "support_url"),
                 "marketingUrl": meta(locale, "marketing_url")}
        # 「このバージョンの新機能」（最初のバージョンには付けられない）
        if os.path.exists(os.path.join(ROOT, "AppStore/metadata", locale, "release_notes.txt")):
            attrs["whatsNew"] = meta(locale, "release_notes")
        if locale in existing:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{existing[locale]['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": existing[locale]["id"], "attributes": attrs}})
        else:
            call("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **attrs},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print("説明・キーワード・宣伝文・URL・新機能: " + ", ".join(LOCALES))


def setup_age_rating(app_info_id):
    """暴力・ギャンブルなどの質問にすべて「なし」と答える（4+）"""
    decl = call("GET", f"/v1/appInfos/{app_info_id}/ageRatingDeclaration")["data"]
    # 「はい／いいえ」で答える項目（未回答だと null なので、型は名前で決める）
    yes_no = {"gambling", "lootBox", "messagingAndChat", "parentalControls", "advertising", "healthOrWellnessTopics",
              "unrestrictedWebAccess", "socialMedia", "ageAssurance", "userGeneratedContent", "socialMediaAgeRestricted",
              "seventeenPlus"}
    skip = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl", "gracRatingClassificationNumber"}
    attrs = {}
    for key, value in decl["attributes"].items():
        if key in skip:
            continue
        if key in yes_no or isinstance(value, bool):
            attrs[key] = False
        else:
            attrs[key] = "NONE"   # 「なし／ときどき／頻繁」で答える項目
    call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {
        "type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
    print("年齢制限: すべて「なし」（4+）")


# --- スクリーンショット -------------------------------------------------------

def upload_file(reservation_path, reservation_type, parent_rel, parent_type, parent_id, file_path):
    """App Store Connect の「予約 → アップロード → 完了」の手順でファイルを送る"""
    with open(file_path, "rb") as f:
        data = f.read()
    created = call("POST", reservation_path, {"data": {
        "type": reservation_type,
        "attributes": {"fileName": os.path.basename(file_path), "fileSize": len(data)},
        "relationships": {parent_rel: {"data": {"type": parent_type, "id": parent_id}}}}})["data"]
    for op in created["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op["requestHeaders"]})
        with urllib.request.urlopen(req):
            pass
    call("PATCH", f"{reservation_path}/{created['id']}", {"data": {
        "type": reservation_type, "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def setup_screenshots():
    app_id = find_app()
    version = editable_version(app_id)
    shots_dir = os.path.join(ROOT, "build/screenshots")
    if not os.path.isdir(shots_dir):
        raise SystemExit("build/screenshots がありません。先に scripts/make_screenshots.sh を実行してください。")
    locs = {x["attributes"]["locale"]: x["id"] for x in
            call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}
    for locale in LOCALES:
        if locale not in locs:
            raise SystemExit(f"{locale} の掲載文がありません。先に metadata を実行してください。")
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{locs[locale]}/appScreenshotSets")["data"]
        desktop = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
        if desktop is None:
            desktop = call("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                "relationships": {"appStoreVersionLocalization": {"data": {
                    "type": "appStoreVersionLocalizations", "id": locs[locale]}}}}})["data"]
        # 入れ直す（同じものが二重にならないように、今あるものは消す）
        for shot in call("GET", f"/v1/appScreenshotSets/{desktop['id']}/appScreenshots")["data"]:
            call("DELETE", f"/v1/appScreenshots/{shot['id']}")
        prefix = SCREENSHOT_LANG[locale] + "-"
        files = sorted(f for f in os.listdir(shots_dir) if f.startswith(prefix) and f.endswith(".png")
                       and f[len(prefix)].isdigit())
        for name in files:
            upload_file("/v1/appScreenshots", "appScreenshots", "appScreenshotSet", "appScreenshotSets",
                        desktop["id"], os.path.join(shots_dir, name))
        print(f"スクリーンショット {locale}: {len(files)} 枚")


# --- 審査メモ -----------------------------------------------------------------

REVIEW_NOTES = """CullCopy copies photos and videos from an SD card (or any folder) into folders by capture date.

No SD card is needed for review:
1. On the Import tab, click "Folder…" next to Source and choose any folder that contains photos.
2. Click "Start Import". Files are copied to Pictures/SD Import, verified, and sorted by date.
3. The Duplicates tab finds files with identical content in one or more folders and lets you compare them side by side.
4. The Pick & Copy tab lists photos from the folders you add, grouped by date. Double-click a photo (or click "Start Preview")
   to open a large preview, then press Return or Space to copy the photo to the chosen destination folder and show the next one.

The app runs in the App Sandbox and only accesses folders the user selects (and Pictures/SD Import).
Tips are consumable in-app purchases that do not unlock any features (heart button in the toolbar)."""


def setup_review_notes():
    """審査メモだけを登録する（連絡先の氏名・電話番号・メールは App Store Connect の画面で入力する）"""
    version = editable_version(find_app())
    detail = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attrs = {"notes": REVIEW_NOTES, "demoAccountRequired": False}
    if detail:
        call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print("審査メモ: 登録しました（ログイン不要）")


# --- ビルド -------------------------------------------------------------------

def attach_build():
    app_id = find_app()
    version = editable_version(app_id)
    builds = call("GET", "/v1/builds", query={"filter[app]": app_id, "filter[processingState]": "VALID",
                                              "filter[preReleaseVersion.version]": version["attributes"]["versionString"],
                                              "sort": "-uploadedDate", "limit": 1})["data"]
    if not builds:
        raise SystemExit("処理が終わったビルドがありません。scripts/appstore.sh でアップロードして、しばらく待ってください。")
    build = builds[0]
    call("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    print(f"ビルド {build['attributes']['version']} をバージョン {version['attributes']['versionString']} に付けました")


# --- 価格と販売地域 ----------------------------------------------------------

def setup_pricing():
    app_id = find_app()
    free = next(p for p in all_pages(f"/v1/apps/{app_id}/appPricePoints", {"filter[territory]": "USA"})
                if float(p["attributes"]["customerPrice"]) == 0)
    call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
        "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    print("価格: 無料")

    territories = [t["id"] for t in all_pages("/v1/territories")]
    try:
        call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
            "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                          "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in territories]})
        print(f"販売地域: {len(territories)} の国と地域（今後増える地域も含む）")
    except SystemExit as e:
        if "409" in str(e) and "already" in str(e).lower():
            print("販売地域: 設定済み")
        else:
            raise


# --- チップ（アプリ内課金） ---------------------------------------------------

# 製品 ID: (参照名, 日本円の価格, {言語: (表示名, 説明)})
TIPS = {
    "com.imblacksteelai.sdimporter.tip.small": ("Tip Small", 160, {
        "ja": ("小さなチップ", "開発を応援する小さなチップです。機能は増えません。"),
        "en-US": ("Small Tip", "A small tip to support development."),
        "ko": ("작은 팁", "개발을 응원하는 작은 팁입니다."),
        "zh-Hans": ("小额小费", "支持开发的小额小费，不会解锁功能。"),
        "zh-Hant": ("小額小費", "支持開發的小額小費，不會解鎖功能。"),
    }),
    "com.imblacksteelai.sdimporter.tip.medium": ("Tip Medium", 480, {
        "ja": ("チップ", "開発を応援するチップです。機能は増えません。"),
        "en-US": ("Tip", "A tip to support development."),
        "ko": ("응원 팁", "개발을 응원하는 팁입니다."),
        "zh-Hans": ("小费", "支持开发的小费，不会解锁功能。"),
        "zh-Hant": ("小費", "支持開發的小費，不會解鎖功能。"),
    }),
    "com.imblacksteelai.sdimporter.tip.large": ("Tip Large", 1000, {
        "ja": ("大きなチップ", "開発を応援する大きなチップです。機能は増えません。"),
        "en-US": ("Big Tip", "A big tip to support development."),
        "ko": ("큰 팁", "개발을 응원하는 큰 팁입니다."),
        "zh-Hans": ("大额小费", "支持开发的大额小费，不会解锁功能。"),
        "zh-Hant": ("大額小費", "支持開發的大額小費，不會解鎖功能。"),
    }),
}
REVIEW_NOTE = ("Consumable tip to support the developer. It does not unlock any features. "
               "Open it from the heart button in the toolbar or the menu bar item \"Support Development\".")


def all_pages(path, query=None):
    query = dict(query or {}, limit=200)
    items, data = [], call("GET", path, query=query)
    items += data["data"]
    while data.get("links", {}).get("next"):
        next_url = data["links"]["next"].replace(API, "")
        req_path, _, qs = next_url.partition("?")
        data = call("GET", req_path + ("?" + qs if qs else ""))
        items += data["data"]
    return items


def setup_tips():
    app_id = find_app()
    existing = {x["attributes"]["productId"]: x for x in all_pages(f"/v1/apps/{app_id}/inAppPurchasesV2")}
    territories = [t["id"] for t in all_pages("/v1/territories")]
    screenshot = os.path.join(ROOT, "build/screenshots/tip-review.png")

    for product_id, (ref_name, yen, texts) in TIPS.items():
        iap = existing.get(product_id)
        if iap is None:
            iap = call("POST", "/v2/inAppPurchases", {"data": {
                "type": "inAppPurchases",
                "attributes": {"name": ref_name, "productId": product_id, "inAppPurchaseType": "CONSUMABLE",
                               "reviewNote": REVIEW_NOTE},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        else:
            call("PATCH", f"/v2/inAppPurchases/{iap['id']}", {"data": {
                "type": "inAppPurchases", "id": iap["id"], "attributes": {"name": ref_name, "reviewNote": REVIEW_NOTE}}})
        iap_id = iap["id"]

        # 表示名と説明
        locs = {x["attributes"]["locale"]: x for x in call("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")["data"]}
        for locale, (name, description) in texts.items():
            attrs = {"name": name, "description": description}
            if locale in locs:
                call("PATCH", f"/v1/inAppPurchaseLocalizations/{locs[locale]['id']}", {"data": {
                    "type": "inAppPurchaseLocalizations", "id": locs[locale]["id"], "attributes": attrs}})
            else:
                call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                    "type": "inAppPurchaseLocalizations", "attributes": {"locale": locale, **attrs},
                    "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})

        # 価格（日本円を基準に、ほかの国は Apple が自動で換算）
        points = all_pages(f"/v2/inAppPurchases/{iap_id}/pricePoints", {"filter[territory]": "JPN"})
        point = min(points, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - yen))
        price = point["attributes"]["customerPrice"]
        call("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "JPN"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {
                              "type": "inAppPurchasePricePoints", "id": point["id"]}}}}]})

        # 販売地域：すべての国と地域（今後増える地域も）
        call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})

        # 審査用スクリーンショット（チップの画面）
        current = call("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot").get("data")
        if current:
            call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{current['id']}")
        upload_file("/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseAppStoreReviewScreenshots",
                    "inAppPurchaseV2", "inAppPurchases", iap_id, screenshot)

        print(f"チップ {product_id.rsplit('.', 1)[-1]}: ¥{float(price):,.0f}・5言語・{len(territories)} の国と地域・審査用画像")


if __name__ == "__main__":
    task = sys.argv[1] if len(sys.argv) > 1 else ""
    if task == "metadata":
        setup_metadata()
    elif task == "screenshots":
        setup_screenshots()
    elif task == "review":
        setup_review_notes()
    elif task == "build":
        attach_build()
    elif task == "pricing":
        setup_pricing()
    elif task == "tips":
        setup_tips()
    else:
        print(__doc__)
        sys.exit(2)
