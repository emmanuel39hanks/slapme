import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "SlapMe — Your Mac Reacts to Every Hit",
  description:
    "A macOS menu bar app that detects physical interactions with your MacBook and triggers customizable audio + visual reactions. Open source, developer-first, endlessly fun.",
  keywords: [
    "macOS",
    "menu bar app",
    "slap",
    "motion detection",
    "sound effects",
    "MacBook",
    "fun",
    "developer tools",
  ],
  openGraph: {
    title: "SlapMe — Your Mac Reacts to Every Hit",
    description:
      "Detect slaps, taps & motion on your MacBook. Trigger sounds, screen effects & more.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body className="min-h-screen bg-white text-gray-950 antialiased font-[family-name:var(--font-geist-sans)]">
        {children}
      </body>
    </html>
  );
}
