import  setupAPIClient  from '../../components/api/api';

export default function NodeService  () {

    const getTreeTableNodes = async () => {
        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
        //console.log('params.lazyEvent', params.lazyEvent.toString())
        try {
            const apiClient = setupAPIClient(undefined);
            // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
            const response = await apiClient.get('/api/recurso')

            // não precisa converter para objeto, pois o axios já faz isso

            const { data } = response.data
           // console.log('.data', JSON.stringify(data))
            
            return {
                data: {
                    data: data[0]
                }
            }
        } catch (err) {
            throw new Error('Erro ao buscar nodes')

        }
    }

    return {
        getTreeTableNodes
    }
  }

  //export default NodeService;