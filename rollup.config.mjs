import { getBabelOutputPlugin } from '@rollup/plugin-babel'
import { nodeResolve } from '@rollup/plugin-node-resolve'
import commonjs from '@rollup/plugin-commonjs'
import json from '@rollup/plugin-json'
import nodeExternals from 'rollup-plugin-node-externals'
import terser from '@rollup/plugin-terser'
import typescript from '@rollup/plugin-typescript'

export default {
  input: './src/index.ts',
  output: {
    file: './dist/extensions/netacea/index.js',
    format: 'cjs',
    sourcemap: false
  },
  plugins: [
    typescript({
      tsconfig: './tsconfig.json'
    }),
    json(),
    commonjs(),
    nodeExternals({
      deps: false
    }),
    nodeResolve({
      browser: false,
      preferBuiltins: false
    }),
    getBabelOutputPlugin({
      presets: ['@babel/preset-env'],
      // All optional newlines and whitespace will be omitted when generating code in compact mode.
      compact: true
    }),
    terser()
  ],
  external: [
    'f5-nodejs',
    './NetaceaConfig.json'
  ]
}
