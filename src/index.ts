// eslint-disable-next-line import/no-unassigned-import
import 'core-js'
// eslint-disable-next-line import/no-unassigned-import
import 'regenerator-runtime/runtime'
import NetaceaF5, {F5ConstructorArgs, IlxServer} from '@netacea/f5'
import * as NetaceaConfig from './NetaceaConfig.json'
// eslint-disable-next-line @typescript-eslint/no-var-requires
const f5 = require('f5-nodejs')
const ilx: IlxServer = new f5.ILXServer()

const netacea = new NetaceaF5(NetaceaConfig as F5ConstructorArgs)
netacea.registerMitigateHandler(ilx)
netacea.registerIngestHandler(ilx)

ilx.listen()
