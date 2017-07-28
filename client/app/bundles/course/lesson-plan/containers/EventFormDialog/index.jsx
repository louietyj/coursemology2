import React from 'react';
import PropTypes from 'prop-types';
import { connect } from 'react-redux';
import { bindActionCreators } from 'redux';
import { isPristine } from 'redux-form';
import FormDialogue from 'lib/components/FormDialogue';
import { formNames } from 'course/lesson-plan/constants';
import * as actionCreators from 'course/lesson-plan/actions';
import EventForm from './EventForm';

const EventFormDialog = ({
  visible,
  disabled,
  formTitle,
  initialValues,
  onSubmit,
  pristine,
  dispatch,
}) => {
  const {
    hideEventForm,
    submitEventForm,
  } = bindActionCreators(actionCreators, dispatch);

  return (
    <FormDialogue
      title={formTitle}
      open={visible}
      submitForm={submitEventForm}
      skipConfirmation={pristine}
      disabled={disabled}
      hideForm={hideEventForm}
    >
      <EventForm {...{ initialValues, onSubmit, disabled }} />
    </FormDialogue>
  );
};

EventFormDialog.defaultProps = {
  visible: false,
  disabled: false,
};

EventFormDialog.propTypes = {
  visible: PropTypes.bool.isRequired,
  disabled: PropTypes.bool.isRequired,
  formTitle: PropTypes.string,
  initialValues: PropTypes.shape({
    id: PropTypes.number,
    eventId: PropTypes.number,
    title: PropTypes.string,
    event_type: PropTypes.string,
    location: PropTypes.string,
    description: PropTypes.string,
    start_at: PropTypes.string,
    end_at: PropTypes.string,
    published: PropTypes.bool,
  }),
  onSubmit: PropTypes.func.isRequired,
  pristine: PropTypes.bool.isRequired,
  dispatch: PropTypes.func.isRequired,
};

export default connect(({ eventForm, ...state }) => ({
  ...eventForm,
  pristine: isPristine(formNames.EVENT)(state),
}))(EventFormDialog);
