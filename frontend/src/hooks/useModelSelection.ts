import { useEffect } from "react";
import { type ModelSelection, useModelStore } from "@/stores/modelStore";
import { useConfig } from "./useOpenCode";

interface UseModelSelectionResult {
  model: ModelSelection | null;
  modelString: string | null;
  recentModels: ModelSelection[];
  setModel: (model: ModelSelection) => void;
}

export function useModelSelection(
  opcodeUrl: string | null | undefined,
  directory?: string,
): UseModelSelectionResult {
  const { data: config } = useConfig(opcodeUrl, directory);
  const { model, recentModels, setModel, syncFromConfig, getModelString } =
    useModelStore();

  useEffect(() => {
    syncFromConfig(config?.model);
  }, [config?.model, syncFromConfig]);

  return {
    model,
    modelString: getModelString(),
    recentModels,
    setModel,
  };
}
