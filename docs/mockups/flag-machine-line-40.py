# Mockup for issue #10: the machine line inside the existing 40 px panel (no added height).
from PIL import Image, ImageDraw, ImageFont, ImageFilter
S=3
F="Everbuff/media/fonts/"
INK=(12,26,34); DIM=(143,161,168); GOLD=(201,173,130); RED=(237,89,77); LAGOON=(31,163,198)
mark=Image.open("Everbuff/media/mark.tga").convert("RGBA").resize((30*S,30*S),Image.LANCZOS)
def bgimg(w,h):
    im=Image.new("RGB",(w,h)); d=ImageDraw.Draw(im)
    for y in range(h):
        t=y/h; d.line([(0,y),(w,y)],fill=(int(70+40*t),int(88+30*t),int(64+20*t)))
    return im
def rect(canvas,box,fill):
    ov=Image.new("RGBA",canvas.size,(0,0,0,0)); ImageDraw.Draw(ov).rectangle(box,fill=fill); canvas.alpha_composite(ov)
def panel(canvas,x,y,human,col,machine,mode):
    d=ImageDraw.Draw(canvas); ICON=44; h=40
    hs={"today":16,"stack":15,"inline":16}[mode]; ms={"stack":10,"inline":11}.get(mode,0)
    hf=ImageFont.truetype("C:/Windows/Fonts/pala.ttf",hs*S)   # stand-in for Morpheus
    mf=ImageFont.truetype(F+"ChakraPetch-Regular.ttf",max(ms,1)*S)
    hw=d.textlength(human,font=hf)/S; mw=d.textlength(machine,font=mf)/S if ms else 0
    w=hw+ICON+16 if mode=="today" else (max(hw,mw)+ICON+16 if mode=="stack" else hw+14+mw+ICON+16)
    rect(canvas,[x*S,y*S,(x+w)*S,(y+h)*S],INK+(224,)); rect(canvas,[x*S,y*S,(x+w)*S,(y+h)*S],(255,255,255,8))
    d.rectangle([(x+ICON-5)*S,(y+10)*S,(x+ICON-2)*S,(y+30)*S],fill=col)
    canvas.alpha_composite(mark,(int((x+5)*S),int((y+5)*S)))
    hy={"today":y+20,"stack":y+14,"inline":y+20}[mode]
    for dx in (-2,0,2):
        for dy in (-2,0,2): d.text(((x+ICON)*S+dx,hy*S+dy),human,font=hf,fill=(0,0,0),anchor="lm")
    d.text(((x+ICON)*S,hy*S),human,font=hf,fill=col,anchor="lm")
    if mode=="stack": d.text(((x+ICON)*S,(y+30)*S),machine,font=mf,fill=DIM,anchor="lm")
    if mode=="inline": d.text(((x+ICON+hw+14)*S,(y+21)*S),machine,font=mf,fill=DIM,anchor="lm")
rows=[("Today: 40 px",'today'),("1. Stacked inside the same 40 px: human line 15, machine line Chakra Petch 10, dim",'stack'),("2. Same row, after the human line: Chakra Petch 11, dim (panel gets wider, not taller)",'inline')]
events=[("Ding!  Level 24",GOLD,"LEVELUP 24 Duskwood"),("You died · Level 23",RED,"DEATH 23 Duskwood"),("Redridge Mountains",LAGOON,"ZONE Redridge Mountains")]
W=1060; H=len(rows)*90+10
canvas=bgimg(W*S,H*S).convert("RGBA"); d=ImageDraw.Draw(canvas)
lab=ImageFont.truetype(F+"ChakraPetch-SemiBold.ttf",12*S)
y=12
for title,mode in rows:
    d.text((20*S,y*S),title,font=lab,fill=(255,255,255))
    x=20
    for human,col,mach in events:
        panel(canvas,x,y+22,human,col,mach,mode); x+= 330 if mode!="inline" else 0
        if mode=="inline": break
    if mode=="inline":
        panel(canvas,450,y+22,events[1][0],events[1][1],events[1][2],mode)
    y+=90
canvas=canvas.resize((W*2,H*2),Image.LANCZOS)
canvas.convert("RGB").save("docs/mockups/flag-machine-line-40.png")
