/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Нативные параметры темы Telegram для бесшовного интерфейса
        tgBg: 'var(--tg-theme-bg-color, #090d16)',
        tgText: 'var(--tg-theme-text-color, #f8fafc)',
        tgHint: 'var(--tg-theme-hint-color, #94a3b8)',
        tgLink: 'var(--tg-theme-link-color, #38bdf8)',
        tgButton: 'var(--tg-theme-button-color, #2563eb)',
        tgButtonText: 'var(--tg-theme-button-text-color, #ffffff)',
        tgSecondaryBg: 'var(--tg-theme-secondary-bg-color, #111827)',
      },
    },
  },
  plugins: [],
}