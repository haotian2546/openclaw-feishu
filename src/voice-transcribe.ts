import { execFile } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

export type TranscribeResult = {
  text: string;
  language?: string;
};

const PYTHON_SCRIPT = `
import sys, json
from faster_whisper import WhisperModel

audio_path = sys.argv[1]
model_size = sys.argv[2] if len(sys.argv) > 2 else "base"

model = WhisperModel(model_size, device="auto", compute_type="auto")
segments, info = model.transcribe(audio_path)
text = "".join(seg.text for seg in segments).strip()
print(json.dumps({"text": text, "language": info.language}))
`;

let cachedScriptPath: string | undefined;

function getScriptPath(): string {
  if (cachedScriptPath && fs.existsSync(cachedScriptPath)) return cachedScriptPath;
  cachedScriptPath = path.join(os.tmpdir(), "openclaw_whisper_transcribe.py");
  fs.writeFileSync(cachedScriptPath, PYTHON_SCRIPT, "utf-8");
  return cachedScriptPath;
}

/**
 * Transcribe an audio file using faster-whisper via Python subprocess.
 */
export async function transcribeAudio(params: {
  audioPath: string;
  modelSize?: string;
  timeoutMs?: number;
}): Promise<TranscribeResult> {
  const { audioPath, modelSize = "base", timeoutMs = 120_000 } = params;

  if (!fs.existsSync(audioPath)) {
    throw new Error(`Audio file not found: ${audioPath}`);
  }

  const scriptPath = getScriptPath();

  return new Promise((resolve, reject) => {
    const python = process.env.WHISPER_PYTHON ?? "/home/nvidia/.openclaw-whisper-venv/bin/python3";
    const env = { ...process.env };
    if (!env.HF_ENDPOINT) env.HF_ENDPOINT = "https://hf-mirror.com";
    execFile(
      python,
      [scriptPath, audioPath, modelSize],
      { timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024, env },
      (err, stdout, stderr) => {
        if (err) {
          reject(new Error(`Whisper transcription failed: ${err.message}\nstderr: ${stderr}`));
          return;
        }
        try {
          const result = JSON.parse(stdout.trim());
          resolve({ text: result.text || "", language: result.language });
        } catch {
          reject(new Error(`Failed to parse whisper output: ${stdout}`));
        }
      },
    );
  });
}
