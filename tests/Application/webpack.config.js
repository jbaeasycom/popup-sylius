const Encore = require('@symfony/webpack-encore');
const path = require('path');

Encore
  .setOutputPath('public/build/shop')
  .setPublicPath('/build/shop')
    .addEntry('app', '../../vendor/sylius/sylius/src/Sylius/Bundle/ShopBundle/Resources/private/entry.js')
    .disableSingleRuntimeChunk()
    .cleanupOutputBeforeBuild()
    .enableSassLoader()
    .autoProvidejQuery()
    .enableSourceMaps(!Encore.isProduction())
    .enableVersioning(Encore.isProduction())
  .autoProvidejQuery();

let webpackConfig = Encore.getWebpackConfig();

webpackConfig.resolve.alias['sylius/ui'] = path.resolve(__dirname, '../../vendor/sylius/sylius/src/Sylius/Bundle/UiBundle/Resources/private/js/');

module.exports = webpackConfig;
