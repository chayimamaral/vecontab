// crudUtils.js

import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';

export const withAuthServerSideProps = (pageHandler?: unknown) => {
  return canSSRAuth(async (ctx) => {
    try {
      const apiClient = setupAPIClient(ctx);
      const response = await apiClient.get('/api/registro');

      const dados = {};

      return {
        props: {
          dados: dados,
        },
      };
    } catch (err: any) {
      // Se for "no rows in result set", apenas continua sem dados
      if (err?.response?.status === 400 && err?.response?.data?.error?.includes('no rows in result set')) {
        return {
          props: {
            dados: {},
          },
        };
      }

      console.log(err);

      return {
        redirect: {
          destination: '/',
          permanent: false,
        },
      };
    }
  });
};
