import { loader, llms } from "fumadocs-core/source";
import { defineDocs } from "fumadocs-mdx/macro";

const docs = defineDocs({
  dir: "content/docs",
});

export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
});

export const docsLlms = llms(source);
