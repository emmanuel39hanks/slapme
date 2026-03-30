"use client";

import { useState, useRef, useCallback } from "react";
import { motion } from "framer-motion";

const sounds = [
  { label: "Bruh", file: "/sounds/bruh.mp3", color: "#f3f4f6" },
  { label: "Sheesh", file: "/sounds/sheesh.mp3", color: "#f3f4f6" },
  { label: "Let's Go", file: "/sounds/letsgo.mp3", color: "#f3f4f6" },
  { label: "Noice", file: "/sounds/noice.mp3", color: "#f3f4f6" },
  { label: "Vine Boom", file: "/sounds/vineboom.mp3", color: "#f3f4f6" },
  { label: "Oof", file: "/sounds/oof.mp3", color: "#f3f4f6" },
];

export function SlapDemo() {
  const [active, setActive] = useState<number | null>(null);
  const audioRefs = useRef<Map<number, HTMLAudioElement>>(new Map());

  const play = useCallback((index: number) => {
    // Stop any currently playing
    audioRefs.current.forEach((audio) => {
      audio.pause();
      audio.currentTime = 0;
    });

    // Create or reuse audio element
    let audio = audioRefs.current.get(index);
    if (!audio) {
      audio = new Audio(sounds[index].file);
      audioRefs.current.set(index, audio);
    } else {
      audio.currentTime = 0;
    }

    audio.play();
    setActive(index);

    audio.onended = () => setActive(null);
    // Fallback reset
    setTimeout(() => setActive(null), 3000);
  }, []);

  return (
    <div className="mx-auto grid max-w-md grid-cols-3 gap-2.5 sm:max-w-lg sm:gap-3">
      {sounds.map((s, i) => (
        <motion.button
          key={i}
          whileTap={{ scale: 0.93 }}
          onClick={() => play(i)}
          className={`relative flex h-[72px] items-center justify-center rounded-2xl text-[14px] font-semibold transition-all duration-150 sm:h-20 ${
            active === i
              ? "bg-gray-950 text-white shadow-[0_0_0_2px_rgba(10,10,10,0.15)]"
              : "bg-gray-50 text-gray-800 hover:bg-gray-100 active:bg-gray-200"
          }`}
        >
          {s.label}
          {active === i && (
            <motion.span
              className="absolute inset-0 rounded-2xl border-2 border-gray-950/20"
              initial={{ opacity: 1, scale: 1 }}
              animate={{ opacity: 0, scale: 1.08 }}
              transition={{ duration: 0.5 }}
            />
          )}
        </motion.button>
      ))}
    </div>
  );
}
