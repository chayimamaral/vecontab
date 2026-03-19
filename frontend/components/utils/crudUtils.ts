// crudUtils.js

import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';

export const withAuthServerSideProps = (pageHandler) => {
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
    } catch (err) {
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
