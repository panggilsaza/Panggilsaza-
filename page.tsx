import { requireUser } from "@/lib/auth";
import Link from "next/link";

export default async function Home() {
  const { profile, supabase } = await requireUser();
  const isAdmin = profile.role === "admin";
  const [{ count: students }, { count: classes }, { count: invoices }] = await Promise.all([
    supabase.from("students").select("*", { count: "exact", head: true }),
    supabase.from("classes").select("*", { count: "exact", head: true }),
    supabase.from("invoices").select("*", { count: "exact", head: true })
  ]);
  return <main style={{maxWidth:1050,margin:"40px auto",padding:20}}>
    <header style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12}}>
      <div><h1 style={{color:"#1766b2",margin:0}}>🐳 panggilsaza.</h1><small>LEARN · GROW · SHINE</small></div>
      <form action="/auth/signout" method="post"><button className="btn">Keluar</button></form>
    </header>
    <section style={{background:"linear-gradient(110deg,#165cad,#58a8ed)",color:"white",padding:28,borderRadius:20,marginTop:24}}>
      <h2>Halo, {profile.full_name}!</h2><p>Selamat datang di PanggilSaza Learning Management System.</p><b>Role: {profile.role.toUpperCase()}</b>
    </section>
    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))",gap:14,marginTop:18}}>
      {isAdmin && <><div className="card"><small>Total siswa</small><h2>{students ?? 0}</h2></div><div className="card"><small>Total kelas</small><h2>{classes ?? 0}</h2></div><div className="card"><small>Invoice</small><h2>{invoices ?? 0}</h2></div></>}
      {!isAdmin && <div className="card"><h3>Portal {profile.role}</h3><p>Menu dan data akan ditampilkan sesuai izin akun Anda.</p></div>}
    </section>
    <section className="card" style={{marginTop:18}}>
      <h3>Program pembelajaran</h3><p>Paket 4, 8, atau 12 pertemuan · 60 atau 90 menit per pertemuan.</p>
      <p>Model kelas: privat individual dan kelompok.</p>
      <Link href="/packages">Lihat paket pembelajaran →</Link>
    </section>
  </main>;
}
