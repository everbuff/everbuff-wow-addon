from PIL import Image, ImageDraw, ImageFont, ImageFilter
S=3  # render scale (UI px * S)
F="Everbuff/media/fonts/"
hero_f=ImageFont.truetype("C:/Windows/Fonts/pala.ttf",16*S)   # stand-in for Morpheus
INK=(12,26,34); BONE=(244,240,235); DIM=(143,161,168); GOLD=(201,173,130); RED=(237,89,77); LAGOON=(31,163,198)
mark=Image.open("Everbuff/media/mark.tga").convert("RGBA").resize((30*S,30*S),Image.LANCZOS)
def bgimg(w,h):
    im=Image.new("RGB",(w,h)); d=ImageDraw.Draw(im)
    for y in range(h):
        t=y/h; d.line([(0,y),(w,y)],fill=(int(70+40*t),int(88+30*t),int(64+20*t)))
    return im.filter(ImageFilter.GaussianBlur(4))
def panel(canvas,x,y,human,col,machine=None,mcol=BONE,msize=12):
    ICON=44
    hw=canvas_draw.textlength(human,font=hero_f)/S
    mf=ImageFont.truetype(F+"ChakraPetch-Regular.ttf",msize*S)
    mw=canvas_draw.textlength(machine,font=mf)/S if machine else 0
    w=min(600,max(hw,mw)+ICON+16); h=56 if machine else 40
    ov=Image.new("RGBA",canvas.size,(0,0,0,0)); od=ImageDraw.Draw(ov)
    od.rectangle([x*S,y*S,(x+w)*S,(y+h)*S],fill=INK+(int(255*0.88),))
    canvas.alpha_composite(ov)
    ov=Image.new("RGBA",canvas.size,(0,0,0,0)); ImageDraw.Draw(ov).rectangle([x*S,y*S,(x+w)*S,(y+h)*S],fill=(255,255,255,8)); canvas.alpha_composite(ov)
    d=ImageDraw.Draw(canvas)
    d.rectangle([(x+ICON-5)*S,(y+h/2-10)*S,(x+ICON-2)*S,(y+h/2+10)*S],fill=col)
    canvas.alpha_composite(mark,(int((x+5)*S),int((y+h/2-15)*S)))
    if machine:
        hy=y+18; my=y+41
    else:
        hy=y+h/2; my=None
    # outline for hero (WoW OUTLINE)
    for dx in (-S//2-1,0,S//2+1):
        for dy in (-S//2-1,0,S//2+1):
            d.text(((x+ICON)*S+dx,hy*S+dy),human,font=hero_f,fill=(0,0,0),anchor="lm")
    d.text(((x+ICON)*S,hy*S),human,font=hero_f,fill=col,anchor="lm")
    if machine: d.text(((x+ICON)*S,my*S),machine,font=mf,fill=mcol,anchor="lm")
    return h
rows=[("Today (no machine line)",None,BONE,12),("Option A as proposed: Chakra Petch 12, bone",True,BONE,12),("Quieter variant: Chakra Petch 11, dim (same tone as the addon's labels)",True,DIM,11)]
events=[("Ding!  Level 24",GOLD,"LEVELUP 24 Duskwood"),("You died · Level 23",RED,"DEATH 23 Duskwood"),("Redridge Mountains",LAGOON,"ZONE Redridge Mountains")]
W=3*300+80; H=len(rows)*110+20
canvas=bgimg(W*S,H*S).convert("RGBA"); canvas_draw=ImageDraw.Draw(canvas)
lab=ImageFont.truetype(F+"ChakraPetch-SemiBold.ttf",12*S)
y=14
for title,m,mc,ms in rows:
    canvas_draw.text((20*S,y*S),title,font=lab,fill=(255,255,255))
    x=20
    for human,col,mach in events:
        panel(canvas,x,y+22,human,col,mach if m else None,mc,ms); x+=300
    y+=110
canvas=canvas.resize((W*2,H*2),Image.LANCZOS)
canvas.convert("RGB").save("docs/mockups/flag-machine-line.png")
print(canvas.size)
