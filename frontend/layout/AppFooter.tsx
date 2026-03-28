/* eslint-disable @next/next/no-img-element */

import React from 'react';

const AppFooter = () => {
    return (
        <div className="layout-footer">
            <img src="/vecontab.svg" alt="Logo" height="20" className="mr-2" />
            Powered by
            <span className="font-medium ml-2">PrimeReact</span>
        </div>
    );
};

export default AppFooter;
