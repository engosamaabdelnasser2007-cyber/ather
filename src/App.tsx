import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { Activity, ArrowLeft, BookOpen, Check, ChevronLeft, CircleHelp, Flower2, Heart, LogIn, Moon, ShieldCheck, Sun, UserRound, X } from "lucide-react";
import { hasSupabaseConfig, supabase } from "./lib/supabase";

type AuthMode = "login" | "signup";
type Prayer = { id: string; label: string; time: string; done: boolean };

const prayers: Prayer[] = [
  { id: "fajr", label: "الفجر", time: "الصلاة الأولى", done: false },
  { id: "dhuhr", label: "الظهر", time: "الصلاة الثانية", done: false },
  { id: "asr", label: "العصر", time: "الصلاة الثالثة", done: false },
  { id: "maghrib", label: "المغرب", time: "الصلاة الرابعة", done: false },
  { id: "isha", label: "العشاء", time: "الصلاة الخامسة", done: false },
];

export default function App() {
  const [dark, setDark] = useState(false);
  const [authMode, setAuthMode] = useState<AuthMode>("login");
  const [showAuth, setShowAuth] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [completed, setCompleted] = useState<string[]>([]);
  const [section, setSection] = useState("الرئيسية");

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => setUserEmail(data.session?.user.email ?? null));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => setUserEmail(session?.user.email ?? null));
    return () => data.subscription.unsubscribe();
  }, [dark]);

  async function handleAuth(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setNotice("");
    if (!supabase) {
      setNotice("الاتصال بقاعدة البيانات غير مُعد بعد. أضف إعدادات Supabase أولًا.");
      return;
    }
    setBusy(true);
    try {
      const result = authMode === "signup"
        ? await supabase.auth.signUp({ email: email.trim(), password })
        : await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (result.error) throw result.error;
      if (authMode === "signup" && !result.data.session) {
        setNotice("تم إنشاء الطلب. راجع بريدك لتأكيد الحساب إذا كان تأكيد البريد مفعّلًا.");
      } else {
        setNotice("تم تسجيل الدخول بنجاح.");
        setShowAuth(false);
      }
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "تعذر إكمال العملية. حاول مرة أخرى.");
    } finally {
      setBusy(false);
    }
  }

  async function signOut() {
    if (!supabase) return;
    const { error } = await supabase.auth.signOut();
    setNotice(error ? "تعذر تسجيل الخروج." : "تم تسجيل الخروج.");
  }

  const nav = [
    { label: "الرئيسية", icon: Flower2 },
    { label: "صلواتي", icon: Sun },
    { label: "القرآن", icon: BookOpen },
    { label: "أذكاري", icon: Heart },
    { label: "رحلتي", icon: Activity },
  ];

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="#home" aria-label="أثر - الرئيسية">
          <span className="brand-mark"><Flower2 size={23} strokeWidth={1.8} /></span>
          <span><strong>أثَر</strong><small>خطوة صغيرة، أثر يدوم</small></span>
        </a>
        <div className="top-actions">
          <button className="icon-button" onClick={() => setDark(v => !v)} aria-label={dark ? "الوضع الفاتح" : "الوضع الداكن"}>{dark ? <Sun size={19} /> : <Moon size={19} />}</button>
          {userEmail ? <button className="button button-soft" onClick={signOut}><UserRound size={17} /> خروج</button> : <button className="button button-primary" onClick={() => setShowAuth(true)}><LogIn size={17} /> دخول</button>}
        </div>
      </header>

      <div className="layout">
        <aside className="sidebar" aria-label="التنقل الرئيسي">
          <p className="eyebrow">مساحتك اليومية</p>
          {nav.map(({ label, icon: Icon }) => (
            <button key={label} className={section === label ? "nav-link active" : "nav-link"} onClick={() => setSection(label)}>
              <Icon size={19} /><span>{label}</span>{section === label && <ChevronLeft className="nav-arrow" size={16} />}
            </button>
          ))}
          <div className="sidebar-note"><ShieldCheck size={19} /><p>رحلتك تخصك<br /><span>خصوصيتك أساس التصميم</span></p></div>
          <button className="help-link" onClick={() => setNotice("أثر يساعدك على متابعة عاداتك اليومية بهدوء، خطوة بخطوة.")}><CircleHelp size={17} /> المساعدة</button>
        </aside>

        <main className="main-content">
          {!hasSupabaseConfig && <div className="setup-alert"><ShieldCheck size={19} /><div><strong>المنصة في مرحلة الإعداد</strong><p>الواجهة جاهزة كبداية، لكن الحفظ السحابي وتسجيل الحسابات لن يعملا قبل ربط مشروع Supabase الحقيقي.</p></div></div>}
          <section className="welcome-card">
            <div className="welcome-copy">
              <span className="pill"><span className="status-dot" /> رحلتك تبدأ بخطوة</span>
              <h1>السلام عليك،<br /><em>أهلًا بك في أثر</em></h1>
              <p>مساحة هادئة تساعدك تتابع عباداتك، وتبني عادات طيبة يومًا بعد يوم، من غير ضغط أو مقارنة.</p>
              <button className="button button-primary" onClick={() => setSection("صلواتي")}>ابدأ رحلتك <ArrowLeft size={17} /></button>
            </div>
            <div className="welcome-art" aria-hidden="true">
              <div className="art-halo" />
              <div className="art-circle"><Flower2 size={100} strokeWidth={0.8} /></div>
              <span className="art-star star-one">✳</span><span className="art-star star-two">✧</span><span className="art-star star-three">✦</span>
              <span className="art-caption">نية طيبة · أثر جميل</span>
            </div>
          </section>

          <div className="section-heading"><div><span className="eyebrow">اليوم</span><h2>{section === "الرئيسية" ? "خطواتك اليومية" : section}</h2></div><span className="date-label">{new Intl.DateTimeFormat("ar-EG", { weekday: "long", day: "numeric", month: "long" }).format(new Date())}</span></div>

          {section === "الرئيسية" || section === "صلواتي" ? (
            <section className="prayer-card">
              <div className="card-heading"><div className="card-icon"><Sun size={20} /></div><div><h3>صلوات اليوم</h3><p>كل خطوة محسوبة، حتى لو كانت صغيرة</p></div><span className="count">{completed.length} / 5</span></div>
              <div className="progress-track"><span style={{ width: `${completed.length * 20}%` }} /></div>
              <div className="prayer-list">
                {prayers.map(prayer => {
                  const done = completed.includes(prayer.id);
                  return <button key={prayer.id} className={done ? "prayer-row done" : "prayer-row"} onClick={() => setCompleted(old => done ? old.filter(id => id !== prayer.id) : [...old, prayer.id])} aria-pressed={done}>
                    <span className="prayer-check">{done ? <Check size={17} /> : <span />}</span>
                    <span className="prayer-label"><strong>{prayer.label}</strong><small>{prayer.time}</small></span>
                    <span className="prayer-state">{done ? "تمت" : "تسجيل الصلاة"} <ChevronLeft size={16} /></span>
                  </button>;
                })}
              </div>
              <p className="local-note">هذه العلامات للمعاينة داخل الصفحة فقط، ولا تُحفظ في حسابك قبل إعداد قاعدة البيانات.</p>
            </section>
          ) : (
            <section className="placeholder-card">
              <div className="placeholder-icon">{section === "القرآن" ? <BookOpen size={28} /> : section === "أذكاري" ? <Heart size={28} /> : <Activity size={28} />}</div>
              <h3>{section === "القرآن" ? "وردك القرآني" : section === "أذكاري" ? "أذكار تطمئن القلب" : "رحلتك وأثر خطواتك"}</h3>
              <p>هذا القسم ضمن مراحل البناء التالية. سنربطه ببياناتك الحقيقية بعد تجهيز قاعدة البيانات.</p>
              <button className="button button-soft" onClick={() => setSection("الرئيسية")}>العودة للرئيسية</button>
            </section>
          )}

          <section className="feature-grid">
            <article className="feature-card"><span className="feature-icon"><BookOpen size={20} /></span><h3>وردك القرآني</h3><p>مساحة لورد يومي هادئ، نكمله خطوة بخطوة.</p><button onClick={() => setSection("القرآن")}>استكشف القسم <ArrowLeft size={15} /></button></article>
            <article className="feature-card"><span className="feature-icon"><Heart size={20} /></span><h3>أذكارك</h3><p>اجعل للذكر مكانًا بسيطًا وثابتًا في يومك.</p><button onClick={() => setSection("أذكاري")}>استكشف القسم <ArrowLeft size={15} /></button></article>
            <article className="feature-card"><span className="feature-icon"><Activity size={20} /></span><h3>أثر الأيام</h3><p>تابع الاستمرارية بتشجيع، بعيدًا عن اللوم.</p><button onClick={() => setSection("رحلتي")}>استكشف القسم <ArrowLeft size={15} /></button></article>
          </section>
          <footer className="footer"><span>أثر © {new Date().getFullYear()}</span><span>بنية طيبة، وخطوة تدوم</span></footer>
        </main>
      </div>

      {notice && <div className="toast" role="status"><span>{notice}</span><button onClick={() => setNotice("")} aria-label="إغلاق"><X size={17} /></button></div>}

      {showAuth && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) setShowAuth(false); }}>
        <section className="auth-modal" role="dialog" aria-modal="true" aria-labelledby="auth-title">
          <button className="modal-close" onClick={() => setShowAuth(false)} aria-label="إغلاق"><X size={20} /></button>
          <div className="modal-mark"><Flower2 size={26} /></div>
          <span className="eyebrow">أهلًا بعودتك</span>
          <h2 id="auth-title">{authMode === "login" ? "سجّل دخولك" : "أنشئ حسابك"}</h2>
          <p className="modal-subtitle">مساحتك الشخصية تبدأ من هنا.</p>
          <form onSubmit={handleAuth}>
            <label>البريد الإلكتروني<input type="email" autoComplete="email" required value={email} onChange={e => setEmail(e.target.value)} placeholder="name@example.com" /></label>
            <label>كلمة المرور<input type="password" autoComplete={authMode === "login" ? "current-password" : "new-password"} minLength={6} required value={password} onChange={e => setPassword(e.target.value)} placeholder="6 أحرف على الأقل" /></label>
            <button className="button button-primary submit-button" type="submit" disabled={busy}>{busy ? "جارٍ التنفيذ..." : authMode === "login" ? "دخول آمن" : "إنشاء الحساب"}</button>
          </form>
          <button className="mode-switch" onClick={() => { setAuthMode(m => m === "login" ? "signup" : "login"); setNotice(""); }}>{authMode === "login" ? "ليس لديك حساب؟ أنشئ حسابًا" : "لديك حساب بالفعل؟ سجّل الدخول"}</button>
          {notice && <p className="form-notice" role="status">{notice}</p>}
          <p className="privacy-note"><ShieldCheck size={15} /> لا تُرسل كلمة المرور إلا إلى Supabase بعد إعداد الاتصال.</p>
        </section>
      </div>}
    </div>
  );
}