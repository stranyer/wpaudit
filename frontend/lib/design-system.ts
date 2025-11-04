// Design System Tokens
export const colors = {
  primary: {
    50: '#f0fdf4',
    100: '#dcfce7',
    500: '#10b981',
    600: '#059669',
    700: '#047857',
  },
  neutral: {
    50: '#f9fafb',
    100: '#f3f4f6',
    200: '#e5e7eb',
    600: '#4b5563',
    700: '#374151',
    900: '#111827',
  },
  status: {
    success: '#16a34a',
    warning: '#ca8a04',
    error: '#dc2626',
    info: '#2563eb',
  }
} as const

export const spacing = {
  xs: '0.5rem',   // 8px
  sm: '1rem',     // 16px
  md: '1.5rem',   // 24px
  lg: '2rem',     // 32px
  xl: '4rem',     // 64px
  '2xl': '6rem',  // 96px
} as const

export const typography = {
  h1: 'text-5xl font-bold leading-tight',
  h2: 'text-3xl font-bold leading-tight',
  h3: 'text-xl font-semibold leading-snug',
  h4: 'text-lg font-medium leading-normal',
  body: 'text-base font-normal leading-relaxed',
  small: 'text-sm leading-normal',
  caption: 'text-xs leading-tight',
} as const

export const containers = {
  sm: 'max-w-2xl',   // 672px - forms
  md: 'max-w-4xl',   // 896px - content
  lg: 'max-w-6xl',   // 1152px - sections
  xl: 'max-w-7xl',   // 1280px - full-width
} as const

