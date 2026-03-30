"use client";

import { useEffect, useState } from "react";

export function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 10);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <div className="fixed top-0 left-0 right-0 z-50 flex justify-center px-4 pt-4">
      <nav
        className={`flex w-full max-w-2xl items-center justify-between rounded-full px-5 py-2.5 transition-all duration-300 ${
          scrolled
            ? "bg-white/70 shadow-[0_1px_3px_rgba(0,0,0,0.04),0_4px_16px_rgba(0,0,0,0.06)] backdrop-blur-[20px] backdrop-saturate-[180%] border border-black/[0.06]"
            : "bg-white/40 backdrop-blur-[12px] backdrop-saturate-[160%] border border-black/[0.04]"
        }`}
      >
        <a href="#" className="flex items-center gap-2">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-gray-950 text-white">
            <svg
              width="13"
              height="13"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2" />
              <path d="M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2" />
              <path d="M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8" />
              <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
            </svg>
          </div>
          <span className="text-[13px] font-semibold tracking-tight">
            SlapMe
          </span>
        </a>

        <div className="flex items-center gap-1">
          <a
            href="https://github.com/emmanuel39hanks/slapme"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full px-3 py-1.5 text-[13px] text-gray-500 transition-colors hover:text-gray-950"
          >
            GitHub
          </a>
          <a
            href="/SlapMe.zip"
            download
            className="rounded-full bg-gray-950 px-4 py-1.5 text-[13px] font-medium text-white transition-all duration-200 hover:bg-gray-800"
          >
            Download
          </a>
        </div>
      </nav>
    </div>
  );
}
