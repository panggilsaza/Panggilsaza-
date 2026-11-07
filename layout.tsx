import "./globals.css";
import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "PanggilSaza | Learning Management",
  description: "PanggilSaza private and group learning management platform."
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="id"><body>{children}</body></html>;
}
