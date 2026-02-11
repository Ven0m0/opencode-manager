import { STTSettings } from "./STTSettings";
import { TTSSettings } from "./TTSSettings";

export function VoiceSettings() {
  return (
    <div className="space-y-6">
      <TTSSettings />
      <STTSettings />
    </div>
  );
}
