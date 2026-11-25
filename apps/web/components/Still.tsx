/**
 * The hero's film still: one person on an empty plain, a minute before sunrise.
 * It is drawn in code so the page has a real frame to compose against before there is photography.
 */
export function Still() {
  return (
    <svg
      className="absolute inset-0 h-full w-full"
      viewBox="0 0 1600 900"
      preserveAspectRatio="xMidYMax slice"
      aria-hidden="true"
    >
      <defs>
        <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#03050a" />
          <stop offset="0.5" stopColor="#0a121d" />
          <stop offset="0.82" stopColor="#1d1418" />
          <stop offset="0.94" stopColor="#4a1d14" />
          <stop offset="1" stopColor="#8a3014" />
        </linearGradient>
        <radialGradient id="dawn" cx="0.5" cy="0.5" r="0.5">
          <stop offset="0" stopColor="#ffd9a8" stopOpacity="0.95" />
          <stop offset="0.12" stopColor="#ff7a2e" stopOpacity="0.85" />
          <stop offset="0.42" stopColor="#ff4d1f" stopOpacity="0.32" />
          <stop offset="1" stopColor="#ff4d1f" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#120c0b" />
          <stop offset="0.25" stopColor="#090909" />
          <stop offset="1" stopColor="#040506" />
        </linearGradient>
        <linearGradient id="rim" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#ffb070" stopOpacity="0" />
          <stop offset="0.5" stopColor="#ffe2bd" stopOpacity="0.95" />
          <stop offset="1" stopColor="#ffb070" stopOpacity="0" />
        </linearGradient>
        <linearGradient id="path" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ff7a2e" stopOpacity="0.5" />
          <stop offset="1" stopColor="#ff7a2e" stopOpacity="0" />
        </linearGradient>
        <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="22" />
        </filter>
        <filter id="softer" x="-30%" y="-80%" width="160%" height="260%">
          <feGaussianBlur stdDeviation="46" />
        </filter>
      </defs>

      <rect width="1600" height="640" fill="url(#sky)" />

      <g fill="#f2eee6">
        <circle cx="212" cy="96" r="1.1" opacity="0.5" />
        <circle cx="388" cy="188" r="0.9" opacity="0.35" />
        <circle cx="560" cy="64" r="1.2" opacity="0.45" />
        <circle cx="741" cy="142" r="0.8" opacity="0.3" />
        <circle cx="905" cy="52" r="1" opacity="0.4" />
        <circle cx="1310" cy="118" r="1.1" opacity="0.4" />
        <circle cx="1466" cy="212" r="0.9" opacity="0.3" />
        <circle cx="130" cy="262" r="0.8" opacity="0.25" />
        <circle cx="1188" cy="238" r="0.7" opacity="0.25" />
      </g>

      <ellipse cx="1090" cy="640" rx="860" ry="470" fill="url(#dawn)" opacity="0.55" />
      <ellipse cx="1090" cy="640" rx="620" ry="330" fill="url(#dawn)" />

      <g filter="url(#soft)">
        <path className="mist-slow" d="M620 418 C760 398 900 424 1040 408 C1180 392 1330 410 1500 396 L1500 412 C1330 428 1180 414 1040 428 C900 442 760 420 620 436 Z" fill="#ff6a2a" opacity="0.32" />
        <path className="mist" d="M260 318 C420 300 590 330 760 312 C900 298 1010 318 1140 308 L1140 320 C1010 332 900 316 760 328 C590 344 420 318 260 334 Z" fill="#c2452a" opacity="0.2" />
        <path className="mist" d="M900 500 C1010 488 1130 506 1260 494 C1370 484 1470 498 1600 488 L1600 500 C1470 512 1370 500 1260 508 C1130 518 1010 502 900 514 Z" fill="#ffa25e" opacity="0.4" />
        <path className="mist-slow" d="M0 232 C150 220 300 244 470 230 L470 240 C300 256 150 234 0 246 Z" fill="#5b3140" opacity="0.28" />
      </g>

      <g filter="url(#softer)" opacity="0.5">
        <ellipse className="mist" cx="520" cy="560" rx="520" ry="26" fill="#3a2a2c" />
        <ellipse className="mist-slow" cx="1260" cy="520" rx="460" ry="20" fill="#5a2a1c" />
      </g>

      <path
        d="M0 640 L0 612 C120 604 210 620 330 610 C470 598 560 624 700 616 C830 608 900 628 1000 630 L1180 630 C1290 628 1360 606 1480 614 C1540 618 1580 610 1600 612 L1600 640 Z"
        fill="#0a0808"
      />

      <rect y="640" width="1600" height="260" fill="url(#ground)" />
      <rect x="560" y="637" width="1060" height="3" fill="url(#rim)" />
      <path d="M1068 642 L1112 642 L1420 900 L640 900 Z" fill="url(#path)" filter="url(#soft)" opacity="0.5" />

      <g transform="translate(1090 640)">
        <path d="M-7 0 L7 0 L-150 235 L-232 235 Z" fill="#000" opacity="0.55" filter="url(#soft)" />
        <g fill="#040405">
          <circle cx="0" cy="-58" r="5.4" />
          <path d="M-7 -50 C-7 -54 7 -54 7 -50 L8.5 -22 L4.6 -22 L4.2 0 L0.8 0 L0 -20 L-0.8 0 L-4.2 0 L-4.6 -22 L-8.5 -22 Z" />
        </g>
      </g>
    </svg>
  );
}
