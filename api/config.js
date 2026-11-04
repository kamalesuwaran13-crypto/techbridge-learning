export default function handler(req,res) {
  res.setHeader("Cache-Control","no-store");
  if(req.method!=="GET"){res.setHeader("Allow","GET");return res.status(405).json({error:"Method not allowed"});}
  const supabaseUrl=process.env.SUPABASE_URL;
  const supabaseAnonKey=process.env.SUPABASE_ANON_KEY;
  if(!supabaseUrl||!supabaseAnonKey)return res.status(503).json({error:"Backend not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY in Vercel."});
  return res.status(200).json({supabaseUrl,supabaseAnonKey});
}
