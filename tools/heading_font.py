import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
src, out_ttf, out_woff2 = sys.argv[1:4]
f = TTFont(src)
f = instancer.instantiateVariableFont(f, {"opsz": 24, "wght": 700, "wdth": 100})
name = f["name"]
for rec in list(name.names):
    if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25): name.removeNames(nameID=rec.nameID)
name.setName("Bricolage Grotesque Heading", 1, 3, 1, 0x409)
name.setName("Bold", 2, 3, 1, 0x409)
name.setName("BricolageGrotesqueHeading-Bold", 3, 3, 1, 0x409)
name.setName("Bricolage Grotesque Heading Bold", 4, 3, 1, 0x409)
name.setName("BricolageGrotesqueHeading-Bold", 6, 3, 1, 0x409)
for rec in list(name.names):
    if rec.platformID == 1: name.removeNames(platformID=1)
f["OS/2"].usWeightClass = 700
f["OS/2"].fsSelection = (f["OS/2"].fsSelection & ~0b1000001) | 0b100000
f["head"].macStyle = 1
# Latin, Latin-1 Supplement, Latin Extended-A, genel noktalama, ₺ € gibi işaretler
unicodes = list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + list(range(0x2010, 0x2028)) + [0x2030, 0x2039, 0x203A, 0x20AC, 0x20BA, 0x2116, 0x2122, 0x2212, 0x2192, 0x00B7]
opts = subset.Options(); opts.layout_features = ["kern", "liga", "calt", "ccmp", "locl", "mark", "mkmk", "case", "tnum", "lnum"]
opts.name_IDs = ["*"]; opts.name_languages = ["*"]; opts.notdef_outline = True
s = subset.Subsetter(opts); s.populate(unicodes=unicodes); s.subset(f)
f.save(out_ttf)
f.flavor = "woff2"; f.save(out_woff2)
