# Processes generated art: removes white backgrounds via flood fill, trims, resizes.
import sys
from PIL import Image, ImageDraw
from collections import deque
A="/cursor/stores/store-d8b962be-a4de-4deb-aa96-07b22c8239b4/grok-bot/agents/c121fcda-8025-4a48-a182-c7425cb296a4/attachments/"
M={
"sprites/hero":"c5dfc880262d48164b5abfb434f31ba32bfa9732b157d2e4ad6d026d13056f78",
"sprites/golem":"45d9bedf944e6c29cff38f6f84184fad57f1efe3453220a341c84b41e9581d66",
"sprites/slime":"57706c6dbce1c870dad94bd3b1f1063fce41952fc103cf8bc9a294d35bdd19cf",
"sprites/goblin":"b7c5677b51978711897fded2b07a4ce6a8338d76f64ac93ddb5b3cf553f83764",
"sprites/wraith":"72e0fe21582a7e8a8f9a12fd4cde66ef72e915844edae138195f67a7f2ca990f",
"sprites/salamander":"e019928750594c8b707cc8a155d4f6245b37d760d7ae07414f7b3135ea34a7df",
"sprites/mushroom":"0728faaa2137c3ab98dd7314dd666d8c54959cfffb92462f01395e8ba30eddbb",
"sprites/boss_dragon":"0302d414509794d3cff43af778a8fb6084c28c4cebe31869b61393f90281101c",
"sprites/boss_frostking":"42e2c0ca13fe63aa29bdf5906ae610b12a708033244ea8b1bb2f8d2538aa4f3d",
"sprites/boss_lich":"9497229fcaef9436141725d85ddc2280b251faf9e31bad2707f77bcf1af8c036",
"portraits/c1":"ec2975f82d333c9f8cd467f07d338736daa46ff727b6c2c3d5c22f838d903197",
"portraits/c2":"4e5252f2bde08fad66699265b814bfb888068592b26898a31160c41ba32d4bd5",
"portraits/c3":"b95ab924b0e31f792912a636392b88263bc1f69f0a730ed1f8dbc541fd374431",
"portraits/c4":"2fa0d0106ebd47e049b000313d0909dbacd56bd89d141c5c3e75d26de440aebd",
"portraits/c5":"44f2f1902e6010431b0c161f9988b13b47614412d505074fca6746082936987c",
"portraits/c6":"ab3778e6ef4fb22ed7c129250fe6a3149f7ec3789574906b825be3f4819d207a",
"portraits/c7":"554819184ba0648e0c3f0f8ecd314458ef1956be7969e1855f2bca636047b316",
"portraits/c8":"ae3331e48fa93e5bb65e5ee2d750a09a251e34d37ca9c22a933a43fe28c53d96",
}
BG={"forest":"234bd1542f87aaba1860c0194c9fbccfb8ff6fe5922ac808e6b5987d6f3a1415","ice":"f19fc03c5807ac87abc8934cd34a63ce13d60748f241b9897cae63ea800a0d40","lava":"c32da8e9a91df63f22d0ea9cd560f60179f462c02e1ecaf68428ce7e5e7333f0","cave":"e1c7ee26ed377d8fb0a57870b9024ef761b2d32efe899cac71e1018d339dcddd"}
def cutout(im,thr=40):
    im=im.convert("RGBA"); w,h=im.size; px=im.load()
    seen=bytearray(w*h); q=deque()
    for x in range(w): q.append((x,0)); q.append((x,h-1))
    for y in range(h): q.append((0,y)); q.append((w-1,y))
    while q:
        x,y=q.popleft()
        if x<0 or y<0 or x>=w or y>=h or seen[y*w+x]: continue
        seen[y*w+x]=1
        r,g,b,a=px[x,y]
        if 255-min(r,g,b)<thr and max(r,g,b)-min(r,g,b)<30:
            px[x,y]=(r,g,b,0)
            q.extend(((x+1,y),(x-1,y),(x,y+1),(x,y-1)))
    # soften fringe: pixels adjacent to transparent and near-white get partial alpha
    for y in range(1,h-1):
        for x in range(1,w-1):
            r,g,b,a=px[x,y]
            if a and (px[x-1,y][3]==0 or px[x+1,y][3]==0 or px[x,y-1][3]==0 or px[x,y+1][3]==0):
                wh=min(r,g,b)
                if wh>180: px[x,y]=(r,g,b,int(255*(255-wh)/75))
    return im.crop(im.getbbox())
for k,v in M.items():
    im=cutout(Image.open(A+v+".jpg"))
    im.thumbnail((512,512) if k.startswith("portraits") else (720,720))
    im.save(f"assets/{k}.png")
for k,v in BG.items():
    Image.open(A+v+".jpg").convert("RGB").resize((1080,1920),Image.LANCZOS).save(f"assets/bg/{k}.jpg",quality=88)
# skills: 3x2 grid of tall tiles -> center squares
s=Image.open(A+"9594ea752466c4b63735f18dd960c6c45590e3b818f0fb49f7560587e4b679f8.jpg").convert("RGB")
W,H=s.size; tw,th=W//3,H//2
names=["blade","meteor","goldrain","haste","rage","ward"]
for i,n in enumerate(names):
    cx,cy=(i%3)*tw+tw//2,(i//3)*th+th//2; r=tw//2-6
    s.crop((cx-r,cy-r,cx+r,cy+r)).resize((192,192),Image.LANCZOS).save(f"assets/ui/skill_{n}.png")
ic=Image.open(A+"968392d4e8ea375ea5bfe0a136719784234ef9b21e262b045792cdda697c0328.jpg").convert("RGB")
ic.resize((512,512),Image.LANCZOS).save("assets/ui/icon_512.png"); ic.resize((192,192),Image.LANCZOS).save("icon.png")
# procedural coin + gem icons
for name,col in (("coin",(255,200,40)),("shard",(120,200,255))):
    im=Image.new("RGBA",(96,96),(0,0,0,0)); d=ImageDraw.Draw(im)
    if name=="coin":
        d.ellipse((6,6,90,90),fill=(150,95,10)); d.ellipse((10,10,86,86),fill=col); d.ellipse((24,24,72,72),outline=(190,130,20),width=5)
    else:
        d.polygon([(48,4),(88,40),(48,92),(8,40)],fill=(40,60,140)); d.polygon([(48,12),(80,40),(48,82),(16,40)],fill=col); d.polygon([(48,12),(64,40),(48,40)],fill=(220,245,255))
    im.save(f"assets/ui/{name}.png")
print("ok")
