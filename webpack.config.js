var path = require('path')
const CopyPlugin = require('copy-webpack-plugin')

module.exports = {
  mode: 'production',
  entry: path.resolve(__dirname, 'src'),
  target: 'node',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'extensions/netacea/index.js'
  },
  module: {
    rules: [
      {
        test: /\.(t|j)sx?$/,
        use: [
          {
            loader: 'babel-loader',
            options: {
              "presets": ["@babel/preset-typescript", "@babel/preset-env"]
            }
          }
        ]
      }
    ],
  },
  // optimization: {
  //   minimize: false
  // },
  resolve: {
    extensions: [ '.tsx', '.ts', '.js' ],
  },
  plugins: [
    new CopyPlugin([
      { from: path.resolve(__dirname, 'rules/netacea_ingest.tcl'), to: 'rules/netacea_ingest.tcl' },
      { from: path.resolve(__dirname, 'rules/netacea_mitigate.tcl'), to: 'rules/netacea_mitigate.tcl' },
      { from: path.resolve(__dirname, 'src/node_version'), to: '' },
      { from: path.resolve(__dirname, 'src/version'), to: '' },
      { from: path.resolve(__dirname, 'src/package.json'), to: 'extensions/netacea/package.json' },
      { from: path.resolve(__dirname, 'src/NetaceaConfig.json'), to: 'extensions/netacea/NetaceaConfig.json' }
    ])
  ],
  externals: {
    './NetaceaConfig.json': 'commonjs2 ./NetaceaConfig.json',
    'f5-nodejs': 'commonjs2 f5-nodejs'
  }
}
