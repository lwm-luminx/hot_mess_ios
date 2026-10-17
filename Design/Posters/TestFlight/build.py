"""Build hot-mess-testflight-poster.html from poster.tpl.html (needs: pip install segno)."""
import segno, io, base64, re, pathlib
HERE = pathlib.Path(__file__).resolve().parent
ICON = HERE / 'hot-mess-icon.svg'
URL1 = 'https://apps.apple.com/app/testflight/id899247664'
URL2 = 'https://testflight.apple.com/join/mcPybJVN'

def qr(url):
    b = io.BytesIO()
    segno.make(url, error='m').save(b, kind='svg', scale=1, border=0, dark='#1a1519', xmldecl=False, svgns=True, nl=False, svgclass='qr')
    s = b.getvalue().decode()
    w = re.search(r'width="(\d+)"', s).group(1)
    s = re.sub(r' width="\d+" height="\d+"', f' viewBox="0 0 {w} {w}"', s, count=1)
    return s.replace('<svg ', '<svg shape-rendering="crispEdges" ', 1)

icon = base64.b64encode(ICON.read_bytes()).decode()
html = (HERE / 'poster.tpl.html').read_text().replace('{{QR1}}', qr(URL1)).replace('{{QR2}}', qr(URL2)).replace('{{ICON}}', icon)
(HERE / 'hot-mess-testflight-poster.html').write_text(html)
