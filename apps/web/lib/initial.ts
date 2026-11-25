import { readPool, type PoolSnapshot } from "./pool";

/** The first read for a page, made on the server. A page still renders if the chain does not answer. */
export async function initialPool(): Promise<PoolSnapshot | null> {
  try {
    return await readPool();
  } catch {
    return null;
  }
}
