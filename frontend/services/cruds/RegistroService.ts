import setupAPIClient from '../../components/api/api';

export default function RegistroService() {

  const getRegistro = async (params) => {

    const apiClient = setupAPIClient(undefined);

    const response = await apiClient.get('/api/registro')

    const dados = response.data

    return { dados }
  }

  const gravaRegistro = async (params) => {

    const apiClient = setupAPIClient(undefined);

    const response = await apiClient.put('/api/registro', {

      razaosocial: params.razaosocial,
      fantasia: params.fantasia,
      endereco: params.endereco,
      bairro: params.bairro,
      cidade: params.cidade,
      estado: params.estado,
      cep: params.cep,
      telefone: params.telefone,
      email: params.email,
      cnpj: params.cnpj,
      ie: params.ie,
      im: params.im,
      observacoes: params.observacoes,
      tenantid: params.tenantid
    })
  }

  return {
    getRegistro,
    gravaRegistro
  }
}