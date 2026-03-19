import React from 'react';
import NotFound from './notfound/index';
import { Page } from '../types/types';

const Custom404: Page = () => {
    return <NotFound />;
};

Custom404.getLayout = function getLayout(page) {
    return page;
};

export default Custom404;
