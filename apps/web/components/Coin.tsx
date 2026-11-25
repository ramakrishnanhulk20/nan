"use client";

import { useEffect, useMemo, useRef } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";

const FACE = 1024;
const FLIP_SECONDS = 0.95;

function displayFamily(): string {
  const value = getComputedStyle(document.documentElement).getPropertyValue("--font-big-shoulders").trim();
  return value || "Arial Narrow, sans-serif";
}

function arcText(g: CanvasRenderingContext2D, text: string, radius: number, size: number, family: string) {
  g.font = `800 ${size}px ${family}`;
  g.textAlign = "center";
  g.textBaseline = "middle";
  const step = (Math.PI * 2) / text.length;
  for (let i = 0; i < text.length; i++) {
    g.save();
    g.translate(FACE / 2, FACE / 2);
    g.rotate(i * step - Math.PI / 2);
    g.translate(0, -radius);
    g.fillText(text[i], 0, 0);
    g.restore();
  }
}

/** One side of the coin as a height picture: white stands proud of the field, which is mid grey. */
function drawFront(canvas: HTMLCanvasElement, name: string, amount: string | null, family: string) {
  const g = canvas.getContext("2d");
  if (!g) return;
  g.fillStyle = "#5c5c5c";
  g.fillRect(0, 0, FACE, FACE);
  g.strokeStyle = "#ffffff";
  g.fillStyle = "#ffffff";
  g.lineWidth = 40;
  g.beginPath();
  g.arc(FACE / 2, FACE / 2, FACE / 2 - 20, 0, Math.PI * 2);
  g.stroke();
  g.lineWidth = 5;
  g.beginPath();
  g.arc(FACE / 2, FACE / 2, FACE / 2 - 132, 0, Math.PI * 2);
  g.stroke();

  const legend = amount ? `GOOD FOR ${amount} BNB · NOTHING LOCKED UP · ` : "CREDIT ON A NAME · NOTHING LOCKED UP · ";
  arcText(g, legend, FACE / 2 - 88, 50, family);

  const word = (name || "nan").toUpperCase();
  let size = 330;
  g.font = `900 ${size}px ${family}`;
  const room = 640;
  const width = g.measureText(word).width;
  if (width > room) size = Math.floor((size * room) / width);
  g.font = `900 ${size}px ${family}`;
  g.textAlign = "center";
  g.textBaseline = "alphabetic";
  g.fillText(word, FACE / 2, FACE / 2 + size * 0.3);
  g.font = `800 64px ${family}`;
  g.fillText(name ? ".AI" : "TAMIL FOR I", FACE / 2, FACE / 2 + size * 0.3 + 96);
}

function drawBack(canvas: HTMLCanvasElement, family: string) {
  const g = canvas.getContext("2d");
  if (!g) return;
  g.fillStyle = "#5c5c5c";
  g.fillRect(0, 0, FACE, FACE);
  g.strokeStyle = "#ffffff";
  g.fillStyle = "#ffffff";
  g.lineWidth = 40;
  g.beginPath();
  g.arc(FACE / 2, FACE / 2, FACE / 2 - 20, 0, Math.PI * 2);
  g.stroke();
  arcText(g, "ONE NAME PER PERSON · FOR LIFE · ", FACE / 2 - 88, 50, family);
  g.beginPath();
  g.arc(FACE / 2, 330, 62, 0, Math.PI * 2);
  g.fill();
  g.fillRect(FACE / 2 - 40, 430, 80, 270);
  g.fillRect(FACE / 2 - 300, 700, 600, 30);
}

function reeding(): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 16;
  canvas.height = 4;
  const g = canvas.getContext("2d");
  if (g) {
    g.fillStyle = "#444";
    g.fillRect(0, 0, 16, 4);
    g.fillStyle = "#fff";
    g.fillRect(0, 0, 8, 4);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = THREE.RepeatWrapping;
  texture.repeat.set(150, 1);
  return texture;
}

function Lighting() {
  const { gl, scene } = useThree();
  useEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const room = new RoomEnvironment();
    const env = pmrem.fromScene(room, 0.04).texture;
    scene.environment = env;
    return () => {
      scene.environment = null;
      env.dispose();
      room.dispose();
      pmrem.dispose();
    };
  }, [gl, scene]);
  return (
    <>
      <directionalLight position={[-4, 5, 6]} intensity={2.2} color="#ffe9cf" />
      <pointLight position={[5, -2.5, 3]} intensity={60} color="#ff4d1f" distance={14} />
      <pointLight position={[-5, -3, -4]} intensity={30} color="#3b5bff" distance={14} />
    </>
  );
}

type CoinProps = { name: string; amount: string | null; still: boolean };

function Struck({ name, amount, still }: CoinProps) {
  const group = useRef<THREE.Group>(null);
  const flipStart = useRef<number | null>(null);
  const first = useRef(true);
  const size = useThree((state) => state.size);

  const { front, back, edge, frontCanvas, backCanvas } = useMemo(() => {
    const frontCanvas = document.createElement("canvas");
    const backCanvas = document.createElement("canvas");
    frontCanvas.width = frontCanvas.height = backCanvas.width = backCanvas.height = FACE;
    const front = new THREE.CanvasTexture(frontCanvas);
    const back = new THREE.CanvasTexture(backCanvas);
    for (const t of [front, back]) {
      t.anisotropy = 8;
      t.center.set(0.5, 0.5);
    }
    // The caps of a cylinder are mapped a quarter turn round from upright once the coin faces the camera.
    front.rotation = Math.PI / 2;
    back.rotation = -Math.PI / 2;
    return { front, back, edge: reeding(), frontCanvas, backCanvas };
  }, []);

  useEffect(() => {
    let alive = true;
    const family = displayFamily();
    const paint = () => {
      if (!alive) return;
      drawFront(frontCanvas, name, amount, family);
      drawBack(backCanvas, family);
      front.needsUpdate = true;
      back.needsUpdate = true;
    };
    paint();
    document.fonts.load(`900 100px ${family}`).then(paint, paint);
    if (first.current) first.current = false;
    else flipStart.current = performance.now() / 1000;
    return () => {
      alive = false;
    };
  }, [name, amount, front, back, frontCanvas, backCanvas]);

  useEffect(
    () => () => {
      front.dispose();
      back.dispose();
      edge.dispose();
    },
    [front, back, edge],
  );

  useFrame((state) => {
    const node = group.current;
    if (!node) return;
    const t = state.clock.elapsedTime;
    let flip = 0;
    if (flipStart.current !== null) {
      const progress = Math.min(1, (performance.now() / 1000 - flipStart.current) / FLIP_SECONDS);
      flip = (1 - Math.pow(1 - progress, 3)) * Math.PI * 2;
      if (progress >= 1) flipStart.current = null;
    }
    const sway = still ? 0 : Math.sin(t * 0.55) * 0.38;
    const nod = still ? 0 : Math.sin(t * 0.37) * 0.07;
    const targetY = sway + state.pointer.x * 0.55 + flip;
    const targetX = nod - state.pointer.y * 0.32;
    node.rotation.y += (targetY - node.rotation.y) * (flip ? 1 : 0.08);
    node.rotation.x += (targetX - node.rotation.x) * 0.08;
    node.position.y = still ? 0 : Math.sin(t * 0.8) * 0.05;
  });

  const scale = Math.min(1, size.width / 560);
  const metal = { color: "#e2a468", metalness: 1, roughness: 0.3, envMapIntensity: 1.25 } as const;

  return (
    <group ref={group} scale={scale}>
      <mesh rotation={[Math.PI / 2, 0, 0]}>
        <cylinderGeometry args={[1.7, 1.7, 0.17, 128, 1]} />
        <meshStandardMaterial attach="material-0" {...metal} roughness={0.42} bumpMap={edge} bumpScale={2.5} />
        <meshStandardMaterial attach="material-1" {...metal} map={front} bumpMap={front} bumpScale={5} />
        <meshStandardMaterial attach="material-2" {...metal} map={back} bumpMap={back} bumpScale={5} />
      </mesh>
    </group>
  );
}

/** A struck coin that carries the visitor's name. It sways, follows the pointer, and turns over when the name changes. */
export default function Coin(props: CoinProps) {
  return (
    <Canvas dpr={[1, 2]} camera={{ position: [0, 0, 7.2], fov: 32 }} gl={{ antialias: true, alpha: true }}>
      <Lighting />
      <Struck {...props} />
    </Canvas>
  );
}
