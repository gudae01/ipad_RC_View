"""Render deterministic Korean UI design references, not native-app screenshots.

Requires Pillow and a Korean font. Run: py -3 design/render_mockups.py
No network assets, real device claims, or drone telemetry are included.
"""
from pathlib import Path
import math
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "mockups"
OUT.mkdir(exist_ok=True)
S = 2
BG, WHITE, TEXT, MUTED, BORDER, ACCENT = "#F8F9FA", "#FFFFFF", "#1A1A1A", "#667085", "#E5E7EB", "#526D82"
FONT = os.environ.get("RCVIEW_KOREAN_FONT", "C:/Windows/Fonts/malgun.ttf")
BOLD = os.environ.get("RCVIEW_KOREAN_BOLD_FONT", "C:/Windows/Fonts/malgunbd.ttf")

def f(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, round(size*S))

class Canvas:
    def __init__(self, w, h, bg=BG):
        self.w,self.h=w,h
        self.im=Image.new("RGB", (w*S,h*S), bg)
        self.d=ImageDraw.Draw(self.im)
    def rect(self, box, fill, radius=0, outline=None):
        self.d.rounded_rectangle(tuple(round(x*S) for x in box), radius=radius*S, fill=fill, outline=outline, width=S)
    def line(self, points, fill=TEXT, width=1.5):
        self.d.line([(int(x*S),int(y*S)) for x,y in points], fill=fill, width=max(1,round(width*S)), joint="curve")
    def text(self, xy, text, size=16, color=TEXT, bold=False, anchor="lt"):
        self.d.text((round(xy[0]*S), round(xy[1]*S)),text,font=f(size,bold),fill=color,anchor=anchor)
    def icon(self, name, x, y, color=TEXT, size=24):
        # Consistent thin outline symbols; no platform glyph dependency.
        u=size/24
        def points(p): return [(x+a*u,y+b*u) for a,b in p]
        def ln(p): self.line(points(p),color,1.6)
        if name=="monitor":
            self.rect((x+2*u,y+3*u,x+22*u,y+17*u),None,2, color)
            ln([(12,17),(12,21)]); ln([(7,21),(17,21)])
        elif name=="full":
            for p in [[(9,3),(3,3),(3,9)],[(15,3),(21,3),(21,9)],[(3,15),(3,21),(9,21)],[(15,21),(21,21),(21,15)]]: ln(p)
        elif name=="exit":
            for p in [[(3,9),(9,9),(9,3)],[(15,3),(15,9),(21,9)],[(3,15),(9,15),(9,21)],[(15,21),(15,15),(21,15)]]: ln(p)
        elif name=="rotate":
            self.d.arc((int((x+4*u)*S),int((y+4*u)*S),int((x+20*u)*S),int((y+20*u)*S)),35,315,fill=color,width=3)
            ln([(15,2),(20,5),(16,9)])
        elif name=="reset":
            ln([(5,4),(5,10),(11,10)])
            self.d.arc((int((x+4*u)*S),int((y+4*u)*S),int((x+21*u)*S),int((y+21*u)*S)),200,525,fill=color,width=3)
        elif name=="cable":
            self.rect((x+7*u,y+2*u,x+17*u,y+10*u),None,2,color)
            ln([(10,2),(10,0)]); ln([(14,2),(14,0)]); ln([(12,10),(12,16),(19,16),(19,22)])
        elif name=="bell":
            ln([(4,17),(6,15),(6,9),(8,5),(12,3),(16,5),(18,9),(18,15),(20,17),(4,17)])
            ln([(10,21),(14,21)])
        elif name=="settings":
            self.d.ellipse((int((x+6*u)*S),int((y+6*u)*S),int((x+18*u)*S),int((y+18*u)*S)),outline=color,width=3)
            for a in range(0,360,45):
                r=math.radians(a); ln([(12+7*math.cos(r),12+7*math.sin(r)),(12+10*math.cos(r),12+10*math.sin(r))])
            self.d.ellipse((int((x+10*u)*S),int((y+10*u)*S),int((x+14*u)*S),int((y+14*u)*S)),outline=color,width=2)
        elif name=="check": ln([(5,12),(10,17),(20,6)])
    def button(self,x,y,label,icon=None,primary=False,width=None):
        width=width or (len(label)*16+56)
        self.rect((x,y,x+width,y+46),ACCENT if primary else WHITE,10,None if primary else BORDER)
        if icon: self.icon(icon,x+14,y+11,WHITE if primary else ACCENT)
        self.text((x+(46 if icon else width/2),y+23),label,15,WHITE if primary else TEXT,True,"lm" if icon else "mm")
    def header(self,connected=False):
        self.icon("monitor",24,26,ACCENT,30)
        self.text((66,29),"RC View",26,bold=True)
        tag="프레임 수신 중 · 예시" if connected else "연결 대기"
        tx=self.w-326 if connected else self.w-242
        self.rect((tx,25,self.w-128,59),"#EDF1F4",8)
        self.text(((tx+self.w-128)/2,42),tag,12,ACCENT,True,"mm")
        self.icon("bell",self.w-103,30,MUTED)
        self.rect((self.w-62,22,self.w-22,62),"#E9EEF2",20)
        self.text((self.w-42,42),"나",14,ACCENT,True,"mm")
    def nav(self,active=0):
        y=self.h-72
        self.rect((0,y,self.w,self.h),WHITE)
        self.line([(0,y),(self.w,y)],BORDER,1)
        for idx,(label,icon) in enumerate([("뷰어","monitor"),("연결","cable"),("설정","settings")]):
            x=self.w/2+(idx-1)*180
            if idx==active: self.rect((x-65,y+10,x+65,y+58),"#EDF1F4",10)
            self.icon(icon,x-38,y+22,ACCENT if idx==active else MUTED,21)
            self.text((x-4,y+33),label,15,ACCENT if idx==active else MUTED,idx==active,"lm")
    def landscape(self,box,label=True):
        x,y,r,b=box; w,h=r-x,b-y
        # A clearly illustrative landscape, intentionally without drone HUD.
        self.rect(box,"#D9E4E7")
        def poly(ps,col): self.d.polygon([(round((x+a*w)*S),round((y+c*h)*S)) for a,c in ps],fill=col)
        poly([(0,.62),(.18,.30),(.31,.48),(.50,.18),(.76,.54),(.91,.29),(1,.44),(1,1),(0,1)],"#A7B8BB")
        poly([(0,.72),(.23,.48),(.41,.67),(.65,.39),(.86,.60),(1,.50),(1,1),(0,1)],"#708D8C")
        poly([(0,.88),(.21,.72),(.42,.90),(.67,.59),(1,.78),(1,1),(0,1)],"#385B59")
        poly([(.35,1),(.49,.79),(.53,.73),(.57,.69),(.61,.66),(.58,.73),(.57,.79),(.48,1)],"#BCCFD0")
        if label:
            self.rect((x+18,y+18,x+222,y+52),"#F8F9FA",8)
            self.text((x+32,y+35),"디자인 시안 · 미리보기 예시",12,ACCENT,True,"lm")
    def save(self,name): self.im.save(OUT/name)

def main(portrait=False):
    c=Canvas(834,1194) if portrait else Canvas(1194,834)
    c.header(True); c.nav()
    left,top,right,bottom=24,90,c.w-24,c.h-96
    c.rect((left,top,right,bottom),WHITE,12,BORDER)
    video=(left+1,top+1,right-1,bottom-(152 if portrait else 112))
    c.rect(video,"#101617",12)
    x,y,r,b=video; iw=r-x; ih=iw*9/16
    if ih>b-y: ih=b-y; iw=ih*16/9
    c.landscape((x+(r-x-iw)/2,y+(b-y-ih)/2,x+(r-x+iw)/2,y+(b-y+ih)/2))
    c.text((44,bottom-(130 if portrait else 94)),"외부 영상 장치",15,bold=True)
    c.text((44,bottom-(101 if portrait else 67)),"장치 이름 · 입력 형식 · 수신 FPS는 실제 연결 후 표시",12,MUTED)
    by=bottom-63
    if portrait:
        c.button(44,by,"확대 초기화","reset",width=154)
        c.button(210,by,"회전","rotate",width=112)
        c.button(c.w-210,by,"전체 화면","full",True,166)
    else:
        c.button(c.w-500,bottom-78,"확대 초기화","reset",width=154)
        c.button(c.w-334,bottom-78,"회전","rotate",width=112)
        c.button(c.w-210,bottom-78,"전체 화면","full",True,166)
    c.save("05-portrait.png" if portrait else "01-viewer.png")

def fullscreen():
    c=Canvas(1194,834,"#000000")
    c.landscape((0,81,1194,753))
    c.rect((24,24,192,70),"#1D2529",10)
    c.icon("exit",38,35,WHITE)
    c.text((72,47),"전체 화면 종료",14,WHITE,True,"lm")
    c.rect((448,746,746,804),"#1D2529",12)
    for x,label,icon in [(470,"초기화","reset"),(568,"회전","rotate"),(666,"맞춤","full")]:
        c.icon(icon,x,760,WHITE,22); c.text((x+30,772),label,12,WHITE,anchor="lm")
    c.save("02-fullscreen.png")

def waiting():
    c=Canvas(1194,834); c.header();c.nav()
    c.rect((24,90,1170,738),WHITE,12,BORDER)
    c.rect((537,245,657,365),"#F0F3F5",12)
    c.icon("cable",566,270,ACCENT,64)
    c.text((597,410),"캡처카드를 연결해 주세요",27,bold=True,anchor="mm")
    c.text((597,453),"연결된 외부 영상 장치를 찾으면 화면이 표시됩니다.",16,MUTED,anchor="mm")
    c.button(420,500,"장치 다시 찾기",primary=True,width=174)
    c.button(606,500,"연결 방법",width=168)
    c.text((597,679),"USB-C iPad · iPadOS 17 이상 · UVC 캡처카드",12,MUTED,anchor="mm")
    c.save("03-waiting.png")

def connection():
    c=Canvas(1194,834);c.header(True);c.nav(1)
    c.text((28,99),"연결",28,bold=True)
    c.text((28,143),"장치와 수신 상태를 확인하세요.",15,MUTED)
    c.rect((24,190,570,490),WHITE,12,BORDER)
    c.text((44,214),"외부 영상 장치",20,bold=True)
    c.rect((44,263,550,340),"#F2F5F7",10,BORDER)
    c.icon("cable",62,285,ACCENT)
    c.text((102,280),"장치 이름이 표시됩니다",16,bold=True)
    c.text((102,310),"실제 검색 결과 · 디자인 예시",12,MUTED)
    c.text((44,375),"다른 장치가 있으면 목록에서 선택할 수 있습니다.",13,MUTED)
    c.button(44,419,"장치 다시 찾기",primary=True,width=170)
    c.button(226,419,"재연결",width=120)
    c.rect((594,190,1170,490),WHITE,12,BORDER)
    c.text((614,214),"입력 및 수신",20,bold=True)
    rows=[("활성 입력 형식","연결 후 표시"),("관측된 수신 FPS","수신 후 표시"),("카메라 권한","기기에서 확인"),("지원 형식","장치 조회 후 선택")]
    for i,(l,r) in enumerate(rows):
        yy=277+i*49
        c.text((614,yy),l,15,MUTED);c.text((1148,yy),r,15,anchor="rt")
        if i<3:c.line([(614,yy+33),(1150,yy+33)],BORDER,1)
    c.rect((24,514,1170,706),WHITE,12,BORDER)
    c.text((44,537),"화면이 보이지 않나요?",19,bold=True)
    c.text((44,579),"캡처카드 연결과 조종기의 정상 영상 출력은 별개입니다.",15,MUTED)
    c.text((44,610),"검은 화면이나 ‘No Signal’ 화면도 영상 프레임으로 수신될 수 있습니다.",15,MUTED)
    c.text((44,653),"조종기 출력 → HDMI 케이블 → UVC 캡처카드 → iPad 순서로 확인하세요.",14,ACCENT)
    c.save("04-connection.png")

if __name__=="__main__":
    main();fullscreen();waiting();connection();main(True)
    thumbs=[]
    for name in ["01-viewer.png","02-fullscreen.png","03-waiting.png","04-connection.png","05-portrait.png"]:
        im=Image.open(OUT/name);im.thumbnail((597,597))
        thumbs.append((name,im.copy()))
    sheet=Image.new("RGB",(1266,1580),BG);d=ImageDraw.Draw(sheet)
    positions=[(24,36),(645,36),(24,495),(645,495),(24,954)]
    labels=["01  메인 뷰어","02  전체 화면","03  연결 대기","04  연결 정보","05  세로 레이아웃"]
    for (name,im),(x,y),label in zip(thumbs,positions,labels):
        d.text((x,y-25),label,font=ImageFont.truetype(BOLD,16),fill=TEXT)
        sheet.paste(im,(x,y))
    sheet.save(OUT/"overview.png")
    print("Rendered 5 mockups at 2x and overview:", OUT)
