import { Nav } from "@/components/Nav";
import { FadeIn } from "@/components/FadeIn";
import { SlapDemo } from "@/components/SlapDemo";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col bg-white">
      <Nav />

      {/* ─── Hero ─── */}
      <section className="relative flex flex-1 flex-col items-center justify-center overflow-hidden px-6 pt-24 pb-16">
        <div className="hero-orb left-1/2 top-0 -translate-x-1/2" />
        <div className="hero-orb-secondary right-0 top-20" />

        <div className="relative mx-auto w-full max-w-3xl text-center">
          <FadeIn>
            <img
              src="/slap-hero.gif"
              alt="Slapping a laptop"
              className="mx-auto mb-8 h-40 w-auto rounded-2xl sm:h-48"
              draggable={false}
            />
          </FadeIn>

          <FadeIn delay={0.05}>
            <h1 className="mx-auto max-w-2xl text-5xl font-semibold leading-[1.08] tracking-tight text-gray-950 sm:text-6xl lg:text-7xl">
              Your Mac reacts to
              <br />
              <span className="text-gray-400">every hit.</span>
            </h1>
          </FadeIn>

          <FadeIn delay={0.1}>
            <p className="mx-auto mt-6 max-w-lg text-lg leading-relaxed text-gray-500">
              Detect taps, hits, and slaps on your MacBook. Trigger sounds and
              visual effects. Try it below.
            </p>
          </FadeIn>

          <FadeIn delay={0.15}>
            <div className="mt-10 flex items-center justify-center gap-4">
              <a
                href="/SlapMe.zip"
                download
                className="inline-flex items-center gap-2.5 rounded-full bg-gray-950 px-6 py-3 text-sm font-medium text-white transition-all duration-200 hover:-translate-y-px hover:bg-gray-800 hover:shadow-lg active:translate-y-0"
              >
                <svg
                  width="15"
                  height="15"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                >
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                </svg>
                Download for Mac
              </a>
              <a
                href="https://github.com"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 text-sm font-medium text-gray-500 transition-colors hover:text-gray-950"
              >
                GitHub
                <svg
                  width="13"
                  height="13"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M7 17L17 7" />
                  <path d="M7 7h10v10" />
                </svg>
              </a>
            </div>
          </FadeIn>

          {/* Sound board */}
          <FadeIn delay={0.2}>
            <div className="mt-14">
              <p className="mb-4 text-[13px] font-medium text-gray-400">
                Tap to preview
              </p>
              <SlapDemo />
            </div>
          </FadeIn>
        </div>
      </section>

      {/* ─── Footer ─── */}
      <footer className="border-t border-black/[0.06] px-6 py-8">
        <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-3 text-[13px] text-gray-400 sm:flex-row">
          <span>&copy; 2026 SlapMe</span>
          <div className="flex gap-6">
            <a
              href="https://github.com"
              target="_blank"
              rel="noopener noreferrer"
              className="transition-colors hover:text-gray-600"
            >
              GitHub
            </a>
            <a
              href="https://twitter.com"
              target="_blank"
              rel="noopener noreferrer"
              className="transition-colors hover:text-gray-600"
            >
              Twitter
            </a>
            <a href="#" className="transition-colors hover:text-gray-600">
              Releases
            </a>
          </div>
        </div>
      </footer>
    </main>
  );
}
