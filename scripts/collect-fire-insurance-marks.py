import argparse
import html
import json
import re
import time
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parents[1]
API_URL = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "YohakuCollectionBot/1.0 (static research archive)"
GENRE_ID = "fire-insurance-marks"
COLLECTED_AT = "2026-06-14"

SELECTION = [
    (61685380, "安田火災海上保険（東京）", "東アジア", "日本の会社名を掲げる標章が、保険制度と企業意匠の輸入を一枚に留める。", ["日本", "東京"]),
    (61794317, "Far Eastern Insurance（上海）", "東アジア", "上海の保険会社名が、都市の国際性を金属板の輪郭へ圧縮している。", ["中国", "上海"]),
    (61723933, "Filipinas Compania de Seguros（マニラ）", "東南アジア", "マニラの社名標章から、植民地期以後の保険表示の広がりを追える。", ["フィリピン", "マニラ"]),
    (61713262, "Eastern United Assurance（シンガポール）", "東南アジア", "海峡植民地の保険会社名が、建物に付ける小型の企業標識として残る。", ["シンガポール", "海峡植民地"]),
    (61619765, "Societe Generale d'Assurances Ottomane（イスタンブール）", "西アジア", "1906年から1918年のオスマン保険会社標章で、帝国末期の商業表示を物質化する。", ["トルコ", "イスタンブール"]),
    (61599023, "Bulgaria Premiere（ソフィア）", "東ヨーロッパ", "赤地と中央紋章、周囲の文字が、国家性と企業識別を同じ面に構成する。", ["ブルガリア", "ソフィア", "紋章"]),
    (61608371, "Elso Magyar Altalanos Biztosito（ブダペスト）", "東ヨーロッパ", "中央の紋章を社名が囲み、壁面で遠くから読める同心円状の識別を作る。", ["ハンガリー", "ブダペスト", "紋章"]),
    (61631266, "Prazska Mestska Pojistovna（プラハ）", "東ヨーロッパ", "赤地の鉄製標章に都市紋章と社名を重ねた、自治体的な保険表示。", ["チェコ", "プラハ", "鉄", "紋章"]),
    (61688559, "Rossia Insurance（サンクトペテルブルク）", "東ヨーロッパ", "青地の大きな金色の星が、文字を読む前に会社を識別させる。", ["ロシア", "サンクトペテルブルク", "星"]),
    (61777466, "Christiania Almindelige Forsikrings（オスロ）", "北ヨーロッパ", "黒地の鉄板に金色の円形紋章と文字を置き、耐久材と視認性を両立する。", ["ノルウェー", "オスロ", "鉄"]),
    (61647932, "Pohja Kinnitusselts（エストニア）", "北ヨーロッパ", "熊の浮彫りを社名が囲み、動物像を企業の記憶装置として使う。", ["エストニア", "熊", "浮彫り"]),
    (61707477, "Milano Compagnia di Assicurazione（ミラノ）", "西ヨーロッパ", "錨、柱、医療記号を金色の円形紋章へ集めたアルミニウム標章。", ["イタリア", "ミラノ", "アルミニウム", "錨"]),
    (61614468, "Mutua Catalana（バルセロナ）", "西ヨーロッパ", "開いた本にも見える青と黄の輪郭が、文字中心の標章に固有の形を与える。", ["スペイン", "バルセロナ", "錫"]),
    (61585404, "Securitas（アントワープ）", "西ヨーロッパ", "黒地に金色の座像を浮かせ、守護や安全の寓意を企業名より先に示す。", ["ベルギー", "アントワープ", "人物像"]),
    (61726333, "Le Nord（パリ）", "西ヨーロッパ", "全面を緑一色とし、浮出し文字だけで識別する抑制された標章。", ["フランス", "パリ", "文字"]),
    (61733159, "Royal Insurance（リヴァプール）", "西ヨーロッパ", "王冠、赤い帯、金色の鳥を銅板の盾形へまとめた紋章的な企業表示。", ["イギリス", "リヴァプール", "銅", "王冠"]),
    (61727910, "British American Assurance（トロント）", "北米", "1833年以後のトロントの標章で、大西洋を越えた保険会社意匠の展開を示す。", ["カナダ", "トロント"]),
    (61845702, "St. Louis Mutual Fire and Marine Insurance（セントルイス）", "北米", "亜鉛板の全面を浮出し社名に使い、図像を抑えた実務的な識別を作る。", ["アメリカ", "セントルイス", "亜鉛", "文字"]),
    (61705827, "South British Insurance（オークランド）", "オセアニア", "ニュージーランドの保険会社標章が、英国系の制度と地域企業の広がりを結ぶ。", ["ニュージーランド", "オークランド"]),
    (61803343, "El Iris（ハバナ）", "カリブ", "1855年以後の相互火災保険会社標章で、カリブ海都市にも同じ壁面制度があったことを示す。", ["キューバ", "ハバナ"]),
]


def clean_html(value):
    value = html.unescape(value or "")
    value = re.sub(r"<style\b[^>]*>.*?</style>", " ", value, flags=re.I | re.S)
    value = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def request_json(session, params):
    for attempt in range(5):
        response = session.get(API_URL, params=params, timeout=60)
        if response.status_code == 429 or 500 <= response.status_code < 600:
            time.sleep(4 * (2**attempt))
            continue
        response.raise_for_status()
        return response.json()
    raise RuntimeError("Commons API did not recover after retries")


def download(session, url, path):
    if path.exists() and path.stat().st_size > 0:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(5):
        response = session.get(url, timeout=90)
        if response.status_code == 429 or 500 <= response.status_code < 600:
            time.sleep(4 * (2**attempt))
            continue
        response.raise_for_status()
        path.write_bytes(response.content)
        return
    raise RuntimeError(f"Image download did not recover: {url}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args()

    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT
    ids = [str(entry[0]) for entry in SELECTION]
    payload = request_json(
        session,
        {
            "action": "query",
            "pageids": "|".join(ids),
            "prop": "imageinfo",
            "iiprop": "url|size|extmetadata",
            "iiurlwidth": 1200,
            "format": "json",
        },
    )
    pages = payload["query"]["pages"]
    items = []
    asset_dir = ROOT / "assets" / "collections" / GENRE_ID

    for page_id, title, family, note, extra_tags in SELECTION:
        page = pages[str(page_id)]
        info = page["imageinfo"][0]
        metadata = info["extmetadata"]
        field = lambda name: clean_html(metadata.get(name, {}).get("value", ""))
        license_name = field("LicenseShortName")
        if license_name.lower() != "public domain":
            raise RuntimeError(f"Unexpected license for {page_id}: {license_name}")

        asset_path = f"assets/collections/{GENRE_ID}/{page_id}.jpg"
        if not args.metadata_only:
            download(session, info.get("thumburl", info["url"]), ROOT / asset_path)

        credit = field("Credit")
        gallery_match = re.search(r"Gallery:\s*(https?://\S+)", credit)
        items.append(
            {
                "id": str(page_id),
                "title": title,
                "family": family,
                "curatorNote": note,
                "localAsset": asset_path,
                "sourceUrl": info["descriptionurl"],
                "originalUrl": info["url"],
                "artist": "作者不詳",
                "repository": "Missouri History Museum",
                "repositoryUrl": gallery_match.group(1) if gallery_match else "https://mohistory.org/collections",
                "credit": "Missouri History Museum via Wikimedia Commons",
                "license": license_name,
                "rights": "Wikimedia Commonsの原典記録でパブリックドメインと表示。",
                "description": field("ImageDescription"),
                "date": field("DateTimeOriginal"),
                "width": info.get("thumbwidth", info["width"]),
                "height": info.get("thumbheight", info["height"]),
                "mediaType": "image",
                "acquiredAt": COLLECTED_AT,
                "tags": ["火災保険", "保険標章", "建築部材", "文字景観", "金属工芸", *extra_tags],
            }
        )

    genre = {
        "id": GENRE_ID,
        "title": "壁に残る火災保険標章",
        "subtitle": "会社の紋章と文字を建物へ留めた小さな金属板",
        "description": "火災保険会社が契約建物の正面に取り付けた金属標章を集めた。社名だけの板から、紋章、星、動物、人物像を使うものまで、保険制度が都市景観の中でどのような視覚記号になったかを各地域で比較する。",
        "method": "Wikimedia Commonsで fire insurance mark、fire insurance plaque を検索し、Missouri History Museum所蔵品のうち、会社名と地域、年代、パブリックドメイン表示を原典メタデータで確認できる20件を地域横断で選定した。",
        "status": "published",
        "tags": ["保険標章", "建築部材", "企業紋章", "文字景観", "金属工芸"],
        "relatedGenres": ["street-letterforms", "dated-rainwater-castings"],
        "mapPosition": {"x": 50, "y": 22},
        "representativeItemId": "61685380",
        "createdAt": COLLECTED_AT,
        "updatedAt": COLLECTED_AT,
        "history": [
            {
                "date": COLLECTED_AT,
                "type": "created",
                "summary": "Missouri History Museum所蔵の各国火災保険標章20件で棚を開始。",
                "diaryPath": "diary/2026-06-14.md",
            }
        ],
        "itemCount": len(items),
        "items": items,
    }
    output = ROOT / "data" / "genres" / f"{GENRE_ID}.json"
    output.write_text(json.dumps(genre, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output} with {len(items)} items")


if __name__ == "__main__":
    main()
