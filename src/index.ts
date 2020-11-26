import 'core-js'
import 'regenerator-runtime/runtime'
import NetaceaF5, { F5ConstructorArgs, IlxServer } from '@netacea/f5'
import * as NetaceaConfig from './NetaceaConfig.json'
const f5 = require('f5-nodejs')
const ilx: IlxServer = new f5.ILXServer()

const netacea = new NetaceaF5(NetaceaConfig as F5ConstructorArgs)
netacea.registerMitigateHandler(ilx)
netacea.registerIngestHandler(ilx)

ilx.listen()
