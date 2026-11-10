#!/bin/bash
# ============================================================
#   الحضور الذكي v42 — النشر على الخادم بأمر واحد
#   الاستخدام:  bash deploy.sh
# ============================================================
# جديد v42:
#   إصلاح خاصية الشعب الدراسية بالإعدادات — كانت مربع الإضافة مقفول
#   «اختر المرحلة أولاً» للأبد حتى بعد اختيار المرحلة (السبب: الاختيار
#   ما كان موصول بالبطاقة من الأساس). هسه:
#   • قائمة المراحل صارت داخل بطاقة الشعب نفسها — تختار المرحلة وتضيف شعبة ج أو د أو أي اسم
#   • التكرار بنفس المرحلة منرفض تلقائياً («هذه الشعبة موجودة مسبقاً»)
#   • كلشي ثاني ما تحرك — الحسابات والطلبة والجلسات والتصدير Excel/PDF كما هي
set -e
cd "$(dirname "$0")"
GREEN='\033'; RED='\033'; YEL='\033'; NC='\033'
step() { echo -e "\n${GREEN}==> $1${NC}"; }
DIRNOW="$(pwd)"

echo "========================================"
echo "   الحضور الذكي — نشر النسخة v42"
echo "   المجلد الحالي: $DIRNOW"
echo "========================================"

step "0) نسخة احتياطية من قاعدة بياناتك قبل أي شي (حماية لبياناتك)"
mkdir -p db
if [ -f db/custom.db ]; then
  BK="db/custom-backup-$(date +%Y%m%d-%H%M%S).db"
  cp db/custom.db "$BK"
  echo -e "${YEL}   خزّينا نسخة قاعدة بياناتك هنا: $BK${NC}"
  echo "   إذا صار أي شي غلط — ارجع لهذا الملف وسمّيه custom.db"
else
  echo "   ماكو قاعدة بيانات قديمة هنا — أول تثبيت، عادي"
fi

step "1) فحص الأدوات"
command -v bun >/dev/null 2>&1 || { echo -e "${RED}✗ bun غير مثبت. ركّبه بالأمر:${NC} curl -fsSL https://bun.sh/install | bash"; exit 1; }
command -v pm2 >/dev/null 2>&1 || { echo -e "${RED}✗ pm2 غير مثبت. ركّبه بالأمر:${NC} npm install -g pm2"; exit 1; }
echo "   bun: $(bun --version) — pm2: $(pm2 --version)"

step "2) فحص مسار قاعدة البيانات (.env)"
if grep -q "REPLACE-WITH-YOUR-SERVER-PATH" .env 2>/dev/null; then
  echo "DATABASE_URL=file:$(pwd)/db/custom.db" > .env
  echo -e "${YEL}   كان المسار placeholder — صلّحناه تلقائياً إلى:${NC}"
  cat .env
else
  echo "   .env تمام:"; cat .env
fi

step "3) كشف فخ المجلد القديم — السبب الأشهر لثبات النسخة القديمة"
if pm2 describe attendance >/dev/null 2>&1; then
  PM2SCRIPT="$(pm2 jlist 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const l=JSON.parse(s);const p=l.find(x=>x.name==="attendance");console.log(p?(p.pm2_env.pm_cwd||""):"")}catch(e){console.log("")}})' 2>/dev/null || true)"
  echo "   pm2 يشغّل البرنامج حالياً من: ${PM2SCRIPT:-غير معروف}"
  if [ -n "$PM2SCRIPT" ] && [ "$PM2SCRIPT" != "$DIRNOW" ]; then
    echo -e "${YEL}   ⚠ انكشف الفخ: البرنامج القديم يشتغل من مجلد ثاني ($PM2SCRIPT)${NC}"
    echo -e "${YEL}     عشان هذا كانت النسخة ثابتة على القديمة مهما رفعت!${NC}"
    echo "   راح نوقف النسخة القديمة ونشغل هذي النسخة الجديدة مكانها..."
    pm2 delete attendance >/dev/null 2>&1 || true
    echo "   ✓ تم — البرنامج راح يشتغل من: $DIRNOW"
  else
    echo "   ✓ تمام — pm2 يشتغل من نفس هذا المجلد"
  fi
else
  echo "   ماكو برنامج مسجل بـ pm2 — أول تشغيل، راح نسجله جديد"
fi

step "4) تثبيت الحزم (دقيقة أو أكثر — طبيعي)"
bun install

step "5) تجهيز قاعدة البيانات — بدون ما نخسر بياناتك"
bunx prisma generate
bunx prisma db push

step "6) بناء النسخة (2-5 دقائق)"
bun run build

step "7) فحص نواتج البناء — لازم الملفات الأساسية تكون موجودة"
FAIL=0
for f in .next/standalone/server.js .next/standalone/public/sw.js .next/standalone/.next/static; do
  if [ -e "$f" ]; then echo "   ✓ $f"; else echo -e "${RED}   ✗ ناقص: $f${NC}"; FAIL=1; fi
done
for f in public/vendor/face-api.js public/models/face/face_recognition_model.bin; do
  if [ -e "$f" ]; then echo "   ✓ $f"; else echo -e "${RED}   ✗ ناقص: $f${NC}"; FAIL=1; fi
done
if ! grep -q "att-v42" public/sw.js 2>/dev/null; then
  echo -e "${RED}   ✗ public/sw.js مو نسخة v42!${NC}"; FAIL=1
fi
if [ "$FAIL" = "1" ]; then
  echo -e "${RED}✗ البناء ناقص! لا تكمل — أعد تنفيذ: bash deploy.sh${NC}"
  exit 1
fi

step "8) إعادة تشغيل الخدمة"
if pm2 describe attendance >/dev/null 2>&1; then
  pm2 restart attendance
  pm2 reload attendance --update-env 2>/dev/null || true
else
  NODE_ENV=production pm2 start "bun .next/standalone/server.js" --name attendance --cwd "$DIRNOW"
fi
pm2 save
sleep 3

step "9) الفحص الحاسم — نسخة البرنامج من داخل الخادم نفسه"
PINGVER="$(curl -s --max-time 10 http://127.0.0.1:3000/api/ping || true)"
echo "   جواب الفحص: $PINGVER"
if echo "$PINGVER" | grep -q '"version":"v42"'; then
  echo -e "${GREEN}   ✅ السيرفر صار v42 فعلاً — الحمدلله${NC}"
elif echo "$PINGVER" | grep -q '"version"'; then
  OLDV="$(echo "$PINGVER" | grep -o '"version":"[^"]*"' || true)"
  echo -e "${RED}   ✗ السيرفر بعده يطلع: $OLDV${NC}"
  echo -e "${RED}   هذا معناه في نسخة ثانية تشتغل بمنفذ 3000 من مجلد قديم!${NC}"
  echo -e "${RED}   نفّذ: pm2 list  — وشوف أكثر من برنامج، أو راجع مجلد التشغيل:${NC}"
  echo -e "${RED}         pm2 describe attendance${NC}"
  exit 1
else
  echo -e "${RED}   ✗ الخدمة ما جاوبت على المنفذ 3000${NC}"
  echo -e "${RED}   شوف السبب بالأمر: pm2 logs attendance --lines 30${NC}"
  exit 1
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ تم نشر v42 بنجاح!${NC}"
echo "========================================"
echo "خطوتين مهمتين بالمتصفح:"
echo "  1) افتح:  http://موقعك/api/ping   ← لازم يطلع  \"version\":\"v42\""
echo "  2) إذا صفحة الموقع ما بطّلت تشوف القديمة: سكر كل تابات"
echo "     الموقع وافتحه من جديد مرة وحدة (أو اضغط Ctrl+Shift+R)"
echo ""
echo "الجديد بهذي النسخة:"
echo "  • إضافة الشعب انصلحت: قائمة المراحل صارت داخل بطاقة «الشعب الدراسية»"
echo "    نفسها — تختار المرحلة وتكتب شعبة ج أو د وتضيف عادي"
echo "  • التكرار بنفس المرحلة ينرفض تلقائياً برسالة واضحة"
echo "  • ما تغير شي ثاني: الحسابات والطلبة والجلسات"
echo "    والتصدير Excel/PDF نفس اللي يشتغل عندك الحمدلله"
