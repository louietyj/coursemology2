import React from 'react';
import { render } from 'react-dom';
import { Provider } from 'react-redux';
import { IntlProvider, addLocaleData } from 'react-intl';

import zh from 'react-intl/locale-data/zh';

import createStore from './store';
import LessonPlanContainer from './containers/LessonPlanContainer';
import translations from '../../../../build/locales/locales.json';

function renderLessonPlan(props) {
  const i18nLocale = $("meta[name='server-context']").data('i18n-locale');
  const availableForeignLocales = { zh };
  const localeWithoutRegionCode = i18nLocale.toLowerCase().split(/[_-]+/)[0];

  let messages;
  if (localeWithoutRegionCode !== 'en' && availableForeignLocales[localeWithoutRegionCode]) {
    addLocaleData(availableForeignLocales[localeWithoutRegionCode]);
    messages = translations[localeWithoutRegionCode] || translations[i18nLocale];
  }

  const store = createStore(props);

  render(
    <Provider store={store}>
      <IntlProvider locale={i18nLocale} messages={messages}>
        <LessonPlanContainer />
      </IntlProvider>
    </Provider>
  , $('#lesson-plan-items')[0]);
}

$.getJSON('', (data) => {
  $(document).ready(() => {
    renderLessonPlan(data);
  });
});
