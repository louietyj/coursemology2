import React from 'react';
import PropTypes from 'prop-types';
import { FormattedMessage } from 'react-intl';
import ReactTooltip from 'react-tooltip';
import { Table, TableBody, TableHeader, TableHeaderColumn, TableRow, TableRowColumn } from 'material-ui/Table';
import { red600, blue600 } from 'material-ui/styles/colors';
import IconButton from 'material-ui/IconButton';
import CircularProgress from 'material-ui/CircularProgress';
import DownloadIcon from 'material-ui/svg-icons/file/file-download';
import HistoryIcon from 'material-ui/svg-icons/action/history';

import { getCourseUserURL, getEditSubmissionURL, getSubmissionLogsURL } from 'lib/helpers/url-builders';
import { assessmentShape } from '../../propTypes';
import { workflowStates } from '../../constants';
import translations from '../../translations';
import submissionsTranslations from './translations';

const styles = {
  unstartedText: {
    color: red600,
    fontWeight: 'bold',
  },
  tableCell: {
    padding: '0.5em',
    textOverflow: 'initial',
    whiteSpace: 'normal',
    wordBreak: 'break-word',
  },
};

export default class SubmissionsTable extends React.Component {

  static renderUnpublishedWarning(submission) {
    if (submission.workflowState !== workflowStates.Graded) return null;

    return (
      <span style={{ display: 'inline-block', marginRight: 5 }}>
        <a data-tip data-for="unpublished-grades" data-offset="{'left' : -8}">
          <i className="fa fa-exclamation-triangle" />
        </a>
        <ReactTooltip id="unpublished-grades" effect="solid">
          <FormattedMessage {...submissionsTranslations.publishNotice} />
        </ReactTooltip>
      </span>
    );
  }

  canDownload() {
    const { assessment, submissions } = this.props;
    return assessment.downloadable && submissions.some(s =>
      s.workflowState !== workflowStates.Unstarted &&
      s.workflowState !== workflowStates.Attempting
    );
  }


  renderSubmissionWorkflowState(submission) {
    const { courseId, assessmentId } = this.props;

    if (submission.workflowState === workflowStates.Unstarted) {
      return (
        <div style={styles.unstartedText}>
          <FormattedMessage {...translations[submission.workflowState]} />
        </div>
      );
    }

    return (
      <div>
        {SubmissionsTable.renderUnpublishedWarning(submission)}
        <a href={getEditSubmissionURL(courseId, assessmentId, submission.id)}>
          <FormattedMessage {...translations[submission.workflowState]} />
        </a>
      </div>
    );
  }

  renderSubmissionLogsLink(submission) {
    const { assessment, courseId, assessmentId } = this.props;

    if (!assessment.passwordProtected || !submission.id) return null;

    return (
      <div data-tip data-for={`access-logs-${submission.id}`}>
        <a href={getSubmissionLogsURL(courseId, assessmentId, submission.id)}>
          <HistoryIcon style={{ color: submission.logCount > 1 ? red600 : blue600 }} />
          <ReactTooltip id={`access-logs-${submission.id}`} effect="solid">
            <FormattedMessage {...submissionsTranslations.accessLogs} />
          </ReactTooltip>
        </a>
      </div>
    );
  }

  renderStudents() {
    const { courseId, assessment, submissions } = this.props;
    return submissions.map(submission => (
      <TableRow key={submission.courseStudent.id}>
        <TableRowColumn style={styles.tableCell}>
          <a href={getCourseUserURL(courseId, submission.courseStudent.id)}>
            {submission.courseStudent.name}
          </a>
        </TableRowColumn>
        <TableRowColumn style={styles.tableCell}>
          {this.renderSubmissionWorkflowState(submission)}
        </TableRowColumn>
        <TableRowColumn style={styles.tableCell}>
          {submission.grade !== undefined ? `${submission.grade} / ${assessment.maximumGrade}` : null}
        </TableRowColumn>
        {assessment.gamified ? <TableRowColumn style={styles.tableCell}>
          {submission.pointsAwarded !== undefined ? submission.pointsAwarded : null}
        </TableRowColumn> : null}
        <TableRowColumn style={{ width: 48, padding: 12 }}>
          {this.renderSubmissionLogsLink(submission)}
        </TableRowColumn>
      </TableRow>
    ));
  }

  renderDownloadButton() {
    const { isDownloading, handleDownload } = this.props;

    if (isDownloading) {
      return <CircularProgress size={24} style={{ margin: 12 }} />;
    }

    return (
      <IconButton
        className="download-submissions"
        iconStyle={{ color: blue600 }}
        onTouchTap={handleDownload}
        disabled={isDownloading || !this.canDownload()}
        data-tip
        data-for="download-btn"
      >
        <DownloadIcon />
        <ReactTooltip id="download-btn" effect="solid">
          <FormattedMessage {...submissionsTranslations.download} />
        </ReactTooltip>
      </IconButton>
    );
  }

  render() {
    const { submissions, assessment } = this.props;

    const tableHeaderColumnFor = field => (
      <TableHeaderColumn style={styles.tableCell}>
        <FormattedMessage {...submissionsTranslations[field]} />
      </TableHeaderColumn>
    );

    return (
      <Table selectable={false}>
        <TableHeader adjustForCheckbox={false} displaySelectAll={false}>
          <TableRow>
            {tableHeaderColumnFor('studentName')}
            {tableHeaderColumnFor('submissionStatus')}
            {tableHeaderColumnFor('grade')}
            {assessment.gamified ? tableHeaderColumnFor('experiencePoints') : null}
            <TableHeaderColumn style={{ width: 48, padding: 0 }}>
              {this.renderDownloadButton()}
            </TableHeaderColumn>
          </TableRow>
        </TableHeader>
        <TableBody displayRowCheckbox={false}>
          {this.renderStudents(submissions)}
        </TableBody>
      </Table>
    );
  }
}

SubmissionsTable.propTypes = {
  submissions: PropTypes.arrayOf(
    PropTypes.shape({
      id: PropTypes.number,
      workflowState: PropTypes.string,
      grade: PropTypes.number,
      pointsAwarded: PropTypes.number,
    })
  ),
  assessment: assessmentShape.isRequired,
  courseId: PropTypes.string.isRequired,
  assessmentId: PropTypes.string.isRequired,
  isDownloading: PropTypes.bool.isRequired,
  handleDownload: PropTypes.func,
};