#!/usr/bin/env python3
import datetime,hashlib,json,re,subprocess
from pathlib import Path
from urllib.parse import urlencode
from fetch_online_evaluation import fetch,ROOT
TITLE='File:2021年4月1日 手雕麻将“末代女师傅”：方寸之间刻琢半世情怀.webm'
def main():
    dest=ROOT/'vision/data/commons-video';dest.mkdir(parents=True,exist_ok=True)
    pinned=ROOT/'vision/reports/online_video_source.json'
    if pinned.exists():
        source=json.loads(pinned.read_text());path=ROOT/source['path']
        if not path.exists():fetch(source['download_url'],path)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:
            raise ValueError('Pinned documentary checksum mismatch')
        print('Verified pinned documentary; source manifest preserved.')
        return
    query={'action':'query','format':'json','prop':'imageinfo','iiprop':'url|extmetadata|sha1|timestamp|size','titles':TITLE}
    meta=dest/'source-metadata.json';fetch('https://commons.wikimedia.org/w/api.php?'+urlencode(query),meta)
    page=next(iter(json.loads(meta.read_text())['query']['pages'].values()));entry=page['imageinfo'][0];tags=entry['extmetadata']
    assert tags['LicenseShortName']['value']=='CC BY 3.0'
    path=dest/'mahjong-craft-PLIHWYxBfrE.webm';url=entry['url'].split('?')[0];fetch(url,path)
    assert hashlib.sha1(path.read_bytes()).hexdigest()==entry['sha1']
    record={'title':TITLE,'source_page':entry['descriptionurl'],'original_youtube':'https://www.youtube.com/watch?v=PLIHWYxBfrE',
            'download_url':url,'revision_timestamp':entry['timestamp'],'author':re.sub('<[^>]+>','',tags['Artist']['value']),
            'license':'CC BY 3.0','license_url':tags['LicenseUrl']['value'],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'path':str(path.relative_to(ROOT)),'retrieved_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (ROOT/'vision/reports/online_video_source.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print(record)
if __name__=='__main__':main()
