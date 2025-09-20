import { defineConfig } from 'vite';
import { svelte } from '@svelte/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  build: {
    lib: {
      entry: 'src/open-webui-plugin.ts',
      name: 'MCPOpenWebUIPlugin',
      fileName: (format) => `open-webui-plugin.${format}.js`,
      formats: ['es', 'umd']
    },
    rollupOptions: {
      external: ['svelte'],
      output: {
        globals: {
          svelte: 'Svelte'
        }
      }
    }
  },
  test: {
    globals: true,
    environment: 'jsdom'
  }
});