#!/usr/bin/env python3
"""Fetch openly licensed real photographs for a small diagnostic, never training."""
import datetime,hashlib,json,re,subprocess
from pathlib import Path
from urllib.parse import urlencode

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'vision/data/commons-real-hands'
FILES=['13orphans.jpg','13yao.JPG','Mahjong ron.jpg',"Monzen chin'itsu.jpg",'Ting-de-base.JPG','Triples-ma-jiang.JPG','Série-ma-jiang.JPG']

def fetch(url,destination):
    subprocess.run(['curl','-fLsS','--max-time','60','-A','MahjongVisionResearch/0.1 (local offline evaluation)',url,'-o',str(destination)],check=True)

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    target=ROOT/'vision/reports/online_sources.json'
    if target.exists():
        for source in json.loads(target.read_text())['sources']:
            path=ROOT/source['path']
            if not path.exists():fetch(source['download_url'],path)
            if hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:
                raise ValueError(f'Pinned source checksum mismatch: {path}')
        print('Verified pinned evaluation photos; source manifest preserved.')
        return
    query={'action':'query','format':'json','prop':'imageinfo','iiprop':'url|extmetadata|sha1|timestamp|size','titles':'|'.join('File:'+f for f in FILES)}
    meta=DEST/'source-metadata.json'
    fetch('https://commons.wikimedia.org/w/api.php?'+urlencode(query),meta)
    info=json.loads(meta.read_text())
    sources=[]
    for page in sorted(info['query']['pages'].values(),key=lambda p:p['pageid']):
        entry=page['imageinfo'][0]; tags=entry['extmetadata']
        license=tags['LicenseShortName']['value']
        if license not in {'CC BY 2.0','CC BY-SA 3.0','CC BY-SA 4.0'}:
            raise ValueError(f'Unreviewed license {license}: {page["title"]}')
        path=DEST/f'commons-{page["pageid"]}.jpg'
        url=entry['url'].split('?')[0]
        fetch(url,path)
        actual_sha1=hashlib.sha1(path.read_bytes()).hexdigest()
        # MediaWiki imageinfo sha1 is hexadecimal on this endpoint.
        if actual_sha1 != entry['sha1']:
            raise ValueError(f'Source checksum mismatch for {path}')
        record={'id':path.stem,'path':str(path.relative_to(ROOT)),'title':page['title'],
                'source_page':entry['descriptionurl'],'download_url':url,'revision_timestamp':entry['timestamp'],
                'author':re.sub('<[^>]+>','',tags['Artist']['value']),
                'license':license,'license_url':tags['LicenseUrl']['value'],
                'width':entry['width'],'height':entry['height'],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'training_overlap':'unknown; independent publisher, no upstream training manifest available',
                'use':'development diagnostic; no local training; upstream overlap unknown'}
        sources.append(record)
        print(record['id'],record['title'],record['license'],flush=True)
    target.write_text(json.dumps({'retrieved_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sources':sources},ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
