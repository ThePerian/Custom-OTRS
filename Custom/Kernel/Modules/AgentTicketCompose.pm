# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTicketCompose;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);
use Mail::Address;
use Encode qw( encode decode );

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    # get form id
    $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check needed stuff
    if ( !$Self->{TicketID} ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('No TicketID is given!'),
            Comment => Translatable('Please contact the admin.'),
        );
    }

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');

    # get config for frontend module
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    # check permissions
    my $Access = $TicketObject->TicketPermission(
        Type     => $Config->{Permission},
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID}
    );

    # error screen, don't show ticket
    if ( !$Access ) {
        return $LayoutObject->NoPermission(
            Message    => "You need $Config->{Permission} permissions!",
            WithHeader => 'yes',
        );
    }

    # get ACL restrictions
    my %PossibleActions = ( 1 => $Self->{Action} );

    my $ACL = $TicketObject->TicketAcl(
        Data          => \%PossibleActions,
        Action        => $Self->{Action},
        TicketID      => $Self->{TicketID},
        ReturnType    => 'Action',
        ReturnSubType => '-',
        UserID        => $Self->{UserID},
    );
    my %AclAction = $TicketObject->TicketAclActionData();

    # check if ACL restrictions exist
    if ( $ACL || IsHashRefWithData( \%AclAction ) ) {

        my %AclActionLookup = reverse %AclAction;

        # show error screen if ACL prohibits this action
        if ( !$AclActionLookup{ $Self->{Action} } ) {
            return $LayoutObject->NoPermission( WithHeader => 'yes' );
        }
    }

    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 1
    );

    # get lock state
    my $TicketBackType = 'TicketBack';
    if ( $Config->{RequiredLock} ) {
        if ( !$TicketObject->TicketLockGet( TicketID => $Self->{TicketID} ) ) {
            $TicketObject->TicketLockSet(
                TicketID => $Self->{TicketID},
                Lock     => 'lock',
                UserID   => $Self->{UserID}
            );
            my $Owner = $TicketObject->TicketOwnerSet(
                TicketID  => $Self->{TicketID},
                UserID    => $Self->{UserID},
                NewUserID => $Self->{UserID},
            );

            # show lock state
            if ( !$Owner ) {
                return $LayoutObject->FatalError();
            }
            $TicketBackType .= 'Undo';
        }
        else {
            my $AccessOk = $TicketObject->OwnerCheck(
                TicketID => $Self->{TicketID},
                OwnerID  => $Self->{UserID},
            );
            if ( !$AccessOk ) {
                my $Output = $LayoutObject->Header(
                    Value     => $Ticket{Number},
                    Type      => 'Small',
                    BodyClass => 'Popup',
                );
                $Output .= $LayoutObject->Warning(
                    Message => Translatable('Sorry, you need to be the ticket owner to perform this action.'),
                    Comment => Translatable('Please change the owner first.'),
                );
                $Output .= $LayoutObject->Footer(
                    Type => 'Small',
                );
                return $Output;
            }
        }
    }

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get params
    my %GetParam;
    for (
        qw(
        From To Cc Bcc Subject Body InReplyTo References ResponseID ReplyArticleID StateID
        ArticleID ArticleTypeID TimeUnits Year Month Day Hour Minute FormID ReplyAll
        )
        )
    {
        $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
    }

    # hash for check duplicated entries
    my %AddressesList;

    my @MultipleCustomer;
    my $CustomersNumber = $ParamObject->GetParam( Param => 'CustomerTicketCounterToCustomer' ) || 0;
    my $Selected = $ParamObject->GetParam( Param => 'CustomerSelected' ) || '';

    # get check item object
    my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

    if ($CustomersNumber) {

        my $CustomerCounter = 1;
        for my $Count ( 1 ... $CustomersNumber ) {
            my $CustomerElement = $ParamObject->GetParam( Param => 'CustomerTicketText_' . $Count );
            my $CustomerSelected = ( $Selected eq $Count ? 'checked="checked"' : '' );
            my $CustomerKey = $ParamObject->GetParam( Param => 'CustomerKey_' . $Count )
                || '';
            my $CustomerQueue = $ParamObject->GetParam( Param => 'CustomerQueue_' . $Count )
                || '';
            if ($CustomerElement) {

                if ( $GetParam{To} ) {
                    $GetParam{To} .= ', ' . $CustomerElement;
                }
                else {
                    $GetParam{To} = $CustomerElement;
                }

                # check email address
                my $CustomerErrorMsg = 'CustomerGenericServerErrorMsg';
                my $CustomerError    = '';
                for my $Email ( Mail::Address->parse($CustomerElement) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsg = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerError = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElement} && $CustomerError eq '' ) {
                    $CustomerErrorMsg = 'IsDuplicatedServerErrorMsg';
                    $CustomerError    = 'ServerError';
                }

                my $CustomerDisabled = '';
                my $CountAux         = $CustomerCounter++;
                if ( $CustomerError ne '' ) {
                    $CustomerDisabled = 'disabled="disabled"';
                    $CountAux         = $Count . 'Error';
                }

                if ( $CustomerQueue ne '' ) {
                    $CustomerQueue = $Count;
                }

                push @MultipleCustomer, {
                    Count            => $CountAux,
                    CustomerElement  => $CustomerElement,
                    CustomerSelected => $CustomerSelected,
                    CustomerKey      => $CustomerKey,
                    CustomerError    => $CustomerError,
                    CustomerErrorMsg => $CustomerErrorMsg,
                    CustomerDisabled => $CustomerDisabled,
                    CustomerQueue    => $CustomerQueue,
                };
                $AddressesList{$CustomerElement} = 1;
            }
        }
    }

    my @MultipleCustomerCc;
    my $CustomersNumberCc = $ParamObject->GetParam( Param => 'CustomerTicketCounterCcCustomer' ) || 0;

    if ($CustomersNumberCc) {
        my $CustomerCounterCc = 1;
        for my $Count ( 1 ... $CustomersNumberCc ) {
            my $CustomerElementCc = $ParamObject->GetParam( Param => 'CcCustomerTicketText_' . $Count );
            my $CustomerKeyCc     = $ParamObject->GetParam( Param => 'CcCustomerKey_' . $Count )
                || '';
            my $CustomerQueueCc = $ParamObject->GetParam( Param => 'CcCustomerQueue_' . $Count )
                || '';

            if ($CustomerElementCc) {

                if ( $GetParam{Cc} ) {
                    $GetParam{Cc} .= ', ' . $CustomerElementCc;
                }
                else {
                    $GetParam{Cc} = $CustomerElementCc;
                }

                # check email address
                my $CustomerErrorMsgCc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorCc    = '';
                for my $Email ( Mail::Address->parse($CustomerElementCc) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsgCc = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerErrorCc = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElementCc} && $CustomerErrorCc eq '' ) {
                    $CustomerErrorMsgCc = 'IsDuplicatedServerErrorMsg';
                    $CustomerErrorCc    = 'ServerError';
                }

                my $CustomerDisabledCc = '';
                my $CountAuxCc         = $CustomerCounterCc++;
                if ( $CustomerErrorCc ne '' ) {
                    $CustomerDisabledCc = 'disabled="disabled"';
                    $CountAuxCc         = $Count . 'Error';
                }

                if ( $CustomerQueueCc ne '' ) {
                    $CustomerQueueCc = $Count;
                }

                push @MultipleCustomerCc, {
                    Count            => $CountAuxCc,
                    CustomerElement  => $CustomerElementCc,
                    CustomerKey      => $CustomerKeyCc,
                    CustomerError    => $CustomerErrorCc,
                    CustomerErrorMsg => $CustomerErrorMsgCc,
                    CustomerDisabled => $CustomerDisabledCc,
                    CustomerQueue    => $CustomerQueueCc,
                };
                $AddressesList{$CustomerElementCc} = 1;
            }
        }
    }

    my @MultipleCustomerBcc;
    my $CustomersNumberBcc = $ParamObject->GetParam( Param => 'CustomerTicketCounterBccCustomer' ) || 0;

    if ($CustomersNumberBcc) {
        my $CustomerCounterBcc = 1;
        for my $Count ( 1 ... $CustomersNumberBcc ) {
            my $CustomerElementBcc = $ParamObject->GetParam( Param => 'BccCustomerTicketText_' . $Count );
            my $CustomerKeyBcc     = $ParamObject->GetParam( Param => 'BccCustomerKey_' . $Count )
                || '';
            my $CustomerQueueBcc = $ParamObject->GetParam( Param => 'BccCustomerQueue_' . $Count )
                || '';

            if ($CustomerElementBcc) {

                if ( $GetParam{Bcc} ) {
                    $GetParam{Bcc} .= ', ' . $CustomerElementBcc;
                }
                else {
                    $GetParam{Bcc} = $CustomerElementBcc;
                }

                # check email address
                my $CustomerErrorMsgBcc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorBcc    = '';
                for my $Email ( Mail::Address->parse($CustomerElementBcc) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                        $CustomerErrorMsgBcc = $CheckItemObject->CheckErrorType()
                            . 'ServerErrorMsg';
                        $CustomerErrorBcc = 'ServerError';
                    }
                }

                # check for duplicated entries
                if ( defined $AddressesList{$CustomerElementBcc} && $CustomerErrorBcc eq '' ) {
                    $CustomerErrorMsgBcc = 'IsDuplicatedServerErrorMsg';
                    $CustomerErrorBcc    = 'ServerError';
                }

                my $CustomerDisabledBcc = '';
                my $CountAuxBcc         = $CustomerCounterBcc++;
                if ( $CustomerErrorBcc ne '' ) {
                    $CustomerDisabledBcc = 'disabled="disabled"';
                    $CountAuxBcc         = $Count . 'Error';
                }

                if ( $CustomerQueueBcc ne '' ) {
                    $CustomerQueueBcc = $Count;
                }

                push @MultipleCustomerBcc, {
                    Count            => $CountAuxBcc,
                    CustomerElement  => $CustomerElementBcc,
                    CustomerKey      => $CustomerKeyBcc,
                    CustomerError    => $CustomerErrorBcc,
                    CustomerErrorMsg => $CustomerErrorMsgBcc,
                    CustomerDisabled => $CustomerDisabledBcc,
                    CustomerQueue    => $CustomerQueueBcc,
                };
                $AddressesList{$CustomerElementBcc} = 1;
            }
        }
    }

    # get Dynamic fields form ParamObject
    my %DynamicFieldValues;

    # get backend object
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value form the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} } =
            $DynamicFieldBackendObject->EditFieldValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ParamObject        => $ParamObject,
            LayoutObject       => $LayoutObject,
            );
    }

    # convert dynamic field values into a structure for ACLs
    my %DynamicFieldACLParameters;
    DYNAMICFIELD:
    for my $DynamicFieldItem ( sort keys %DynamicFieldValues ) {
        next DYNAMICFIELD if !$DynamicFieldItem;
        next DYNAMICFIELD if !$DynamicFieldValues{$DynamicFieldItem};

        $DynamicFieldACLParameters{ 'DynamicField_' . $DynamicFieldItem } = $DynamicFieldValues{$DynamicFieldItem};
    }
    $GetParam{DynamicField} = \%DynamicFieldACLParameters;

    # transform pending time, time stamp based on user time zone
    if (
        defined $GetParam{Year}
        && defined $GetParam{Month}
        && defined $GetParam{Day}
        && defined $GetParam{Hour}
        && defined $GetParam{Minute}
        )
    {
        %GetParam = $LayoutObject->TransformDateSelection(
            %GetParam,
        );
    }

    # get needed objects
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $MainObject        = $Kernel::OM->Get('Kernel::System::Main');

    # send email
    if ( $Self->{Subaction} eq 'SendEmail' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # get valid state id
        if ( !$GetParam{StateID} ) {
            my %Ticket = $TicketObject->TicketGet(
                TicketID => $Self->{TicketID},
                UserID   => 1,
            );
            $GetParam{StateID} = $Ticket{StateID};
        }

        my %StateData = $Kernel::OM->Get('Kernel::System::State')->StateGet( ID => $GetParam{StateID} );

        my %Error;

        # get check item object
        my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Line . 'ErrorType' } = $Line . $CheckItemObject->CheckErrorType() . 'ServerErrorMsg';
                    $Error{ $Line . 'Invalid' }   = 'ServerError';
                }
                my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
                    Address => $Email->address()
                );
                if ($IsLocal) {
                    $Error{ $Line . 'IsLocalAddress' } = 'ServerError';
                }
            }
        }

        if ( $Error{ToIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'ToIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{CcIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'CcIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{BccIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'BccIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        # If is an action about attachments
        my $IsUpload = 0;

        # attachment delete
        my @AttachmentIDs = map {
            my ($ID) = $_ =~ m{ \A AttachmentDelete (\d+) \z }xms;
            $ID ? $ID : ();
        } $ParamObject->GetParamNames();

        COUNT:
        for my $Count ( reverse sort @AttachmentIDs ) {
            my $Delete = $ParamObject->GetParam( Param => "AttachmentDelete$Count" );
            next COUNT if !$Delete;
            $Error{AttachmentDelete} = 1;
            $UploadCacheObject->FormIDRemoveFile(
                FormID => $Self->{FormID},
                FileID => $Count,
            );
            $IsUpload = 1;
        }

        # attachment upload
        if ( $ParamObject->GetParam( Param => 'AttachmentUpload' ) ) {
            $IsUpload                = 1;
            %Error                   = ();
            $Error{AttachmentUpload} = 1;
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param => 'FileUpload',
            );
            $UploadCacheObject->FormIDAddFile(
                FormID      => $Self->{FormID},
                Disposition => 'attachment',
                %UploadStuff,
            );
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get time object
        my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

        # check pending date
        if ( $StateData{TypeName} && $StateData{TypeName} =~ /^pending/i ) {
            if ( !$TimeObject->Date2SystemTime( %GetParam, Second => 0 ) ) {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
            if (
                $TimeObject->Date2SystemTime( %GetParam, Second => 0 )
                < $TimeObject->SystemTime()
                )
            {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
        }

        # check if at least one recipient has been chosen
        if ( $IsUpload == 0 ) {
            if ( !$GetParam{To} ) {
                $Error{'ToInvalid'} = 'ServerError';
            }
        }

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    if ( $IsUpload == 0 ) {
                        $Error{ $Line . 'Invalid' } = 'ServerError';
                    }
                }
            }
        }

        # check subject
        if ( !$IsUpload && !$GetParam{Subject} ) {
            $Error{SubjectInvalid} = ' ServerError';
        }

        # check body
        if ( !$IsUpload && !$GetParam{Body} ) {
            $Error{BodyInvalid} = ' ServerError';
        }

        # check time units
        if (
            $ConfigObject->Get('Ticket::Frontend::AccountTime')
            && $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
            && $GetParam{TimeUnits} eq ''
            )
        {
            if ( !$IsUpload ) {
                $Error{TimeUnitsInvalid} = 'ServerError';
            }
        }

        # prepare subject
        my $Tn = $TicketObject->TicketNumberLookup( TicketID => $Self->{TicketID} );
        $GetParam{Subject} = $TicketObject->TicketSubjectBuild(
            TicketNumber => $Tn,
            Subject      => $GetParam{Subject} || '',
        );

        my %ArticleParam;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' )
        {

            # use ticket QueueID in compose modules
            $GetParam{QueueID} = $Ticket{QueueID};

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }
                my $Object = $Jobs{$Job}->{Module}->new( %{$Self}, Debug => $Self->{Debug} );

                # get params
                for ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # ticket params
                %ArticleParam = (
                    %ArticleParam,
                    $Object->ArticleOption( %GetParam, Config => $Jobs{$Job} ),
                );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $PossibleValuesFilter;

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        Action        => $Self->{Action},
                        TicketID      => $Self->{TicketID},
                        ReturnType    => 'Ticket',
                        ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data          => \%AclData,
                        UserID        => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        %{$PossibleValuesFilter} = map { $_ => $PossibleValues->{$_} }
                            keys %Filter;
                    }
                }
            }

            my $ValidationResult;

            # do not validate on attachment upload
            if ( !$IsUpload ) {

                $ValidationResult = $DynamicFieldBackendObject->EditFieldValueValidate(
                    DynamicFieldConfig   => $DynamicFieldConfig,
                    PossibleValuesFilter => $PossibleValuesFilter,
                    ParamObject          => $ParamObject,
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                );

                if ( !IsHashRefWithData($ValidationResult) ) {
                    return $LayoutObject->ErrorScreen(
                        Message =>
                            "Could not perform validation on field $DynamicFieldConfig->{Label}!",
                        Comment => Translatable('Please contact the admin.'),
                    );
                }

                # propagate validation error to the Error variable to be detected by the frontend
                if ( $ValidationResult->{ServerError} ) {
                    $Error{ $DynamicFieldConfig->{Name} } = ' ServerError';
                }
            }

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                PossibleValuesFilter => $PossibleValuesFilter,
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                ServerError  => $ValidationResult->{ServerError}  || '',
                ErrorMessage => $ValidationResult->{ErrorMessage} || '',
                LayoutObject => $LayoutObject,
                ParamObject  => $ParamObject,
                AJAXUpdate   => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # check if there is an error
        if (%Error) {

            my $Output = $LayoutObject->Header(
                Value     => $Ticket{TicketNumber},
                Type      => 'Small',
                BodyClass => 'Popup',
            );
            $GetParam{StandardResponse} = $GetParam{Body};
            $Output .= $Self->_Mask(
                TicketID   => $Self->{TicketID},
                NextStates => $Self->_GetNextStates(
                    %GetParam,
                ),
                ResponseFormat      => $LayoutObject->Ascii2Html( Text => $GetParam{Body} ),
                Errors              => \%Error,
                MultipleCustomer    => \@MultipleCustomer,
                MultipleCustomerCc  => \@MultipleCustomerCc,
                MultipleCustomerBcc => \@MultipleCustomerBcc,
                Attachments         => \@Attachments,
                GetParam            => \%GetParam,
                TicketBackType      => $TicketBackType,
                %Ticket,
                DynamicFieldHTML => \%DynamicFieldHTML,
                %GetParam,
            );
            $Output .= $LayoutObject->Footer(
                Type => 'Small',
            );
            return $Output;
        }

        # replace <OTRS_TICKET_STATE> with next ticket state name
        if ( $StateData{Name} ) {
            $GetParam{Body} =~ s/<OTRS_TICKET_STATE>/$StateData{Name}/g;
            $GetParam{Body} =~ s/&lt;OTRS_TICKET_STATE&gt;/$StateData{Name}/g;
        }

        # get pre loaded attachments
        my @AttachmentData = $UploadCacheObject->FormIDGetAllFilesData(
            FormID => $Self->{FormID},
        );

        # get submit attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );
        if (%UploadStuff) {
            push @AttachmentData, \%UploadStuff;
        }

        # get recipients
        my $Recipients = '';
        LINE:
        for my $Line (qw(To Cc Bcc)) {

            next LINE if !$GetParam{$Line};

            if ($Recipients) {
                $Recipients .= ', ';
            }
            $Recipients .= $GetParam{$Line};
        }

        my $MimeType = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $MimeType = 'text/html';

            # remove unused inline images
            my @NewAttachmentData;
            ATTACHMENT:
            for my $Attachment (@AttachmentData) {
                my $ContentID = $Attachment->{ContentID};
                if (
                    $ContentID
                    && ( $Attachment->{ContentType} =~ /image/i )
                    && ( $Attachment->{Disposition} eq 'inline' )
                    )
                {
                    my $ContentIDHTMLQuote = $LayoutObject->Ascii2Html(
                        Text => $ContentID,
                    );

                    # workaround for link encode of rich text editor, see bug#5053
                    my $ContentIDLinkEncode = $LayoutObject->LinkEncode($ContentID);
                    $GetParam{Body} =~ s/(ContentID=)$ContentIDLinkEncode/$1$ContentID/g;

                    # ignore attachment if not linked in body
                    next ATTACHMENT
                        if $GetParam{Body} !~ /(\Q$ContentIDHTMLQuote\E|\Q$ContentID\E)/i;
                }

                # remember inline images and normal attachments
                push @NewAttachmentData, \%{$Attachment};
            }
            @AttachmentData = @NewAttachmentData;

            # verify HTML document
            $GetParam{Body} = $LayoutObject->RichTextDocumentComplete(
                String => $GetParam{Body},
            );
        }

        # if there is no ArticleTypeID, use the default value
        my $ArticleTypeID = $GetParam{ArticleTypeID} // $TicketObject->ArticleTypeLookup(
            ArticleType => $Config->{DefaultArticleType},
        );

        # error page
        if ( !$ArticleTypeID ) {
            return $LayoutObject->ErrorScreen(
                Comment => Translatable('Can not determine the ArticleType, Please contact the admin.'),
            );
        }
        
        # get template
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
        
        # get salutation
        $GetParam{Salutation} = $TemplateGenerator->Salutation(
            TicketID => $Self->{TicketID},
            Data     => \%GetParam,
            UserID   => $Self->{UserID},
        );

        # get signature
        $GetParam{Signature} = $TemplateGenerator->Signature(
            TicketID => $Self->{TicketID},
            Data     => \%GetParam,
            UserID   => $Self->{UserID},
        );
        
        my $ReplyBody = $Self->_GetReplyBody(
            ArticleTypeID => $ArticleTypeID,
            %DynamicFieldValues,
            %GetParam,
            );

        # send email
        my $ArticleID = $TicketObject->ArticleSend(
            ArticleTypeID  => $ArticleTypeID,
            SenderType     => 'agent',
            TicketID       => $Self->{TicketID},
            HistoryType    => 'SendAnswer',
            HistoryComment => "\%\%$Recipients",
            From           => $GetParam{From},
            To             => $GetParam{To},
            Cc             => $GetParam{Cc},
            Bcc            => $GetParam{Bcc},
            Subject        => $GetParam{Subject},
            UserID         => $Self->{UserID},
            Body           => $GetParam{Body},
            ReplyBody      => $ReplyBody,
            InReplyTo      => $GetParam{InReplyTo},
            References     => $GetParam{References},
            Charset        => $LayoutObject->{UserCharset},
            MimeType       => $MimeType,
            Attachment     => \@AttachmentData,
            %ArticleParam,
        );

        # error page
        if ( !$ArticleID ) {
            return $LayoutObject->ErrorScreen();
        }

        # time accounting
        if ( $GetParam{TimeUnits} ) {
            $TicketObject->TicketAccountTime(
                TicketID  => $Self->{TicketID},
                ArticleID => $ArticleID,
                TimeUnit  => $GetParam{TimeUnits},
                UserID    => $Self->{UserID},
            );
        }

        # set dynamic fields
        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # set the object ID (TicketID or ArticleID) depending on the field configration
            my $ObjectID = $DynamicFieldConfig->{ObjectType} eq 'Article' ? $ArticleID : $Self->{TicketID};

            # set the value
            my $Success = $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $ObjectID,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                UserID             => $Self->{UserID},
            );
        }

        # set state
        $TicketObject->TicketStateSet(
            TicketID  => $Self->{TicketID},
            ArticleID => $ArticleID,
            StateID   => $GetParam{StateID},
            UserID    => $Self->{UserID},
        );

        # should I set an unlock?
        if ( $StateData{TypeName} =~ /^close/i ) {
            $TicketObject->TicketLockSet(
                TicketID => $Self->{TicketID},
                Lock     => 'unlock',
                UserID   => $Self->{UserID},
            );
        }

        # set pending time
        elsif ( $StateData{TypeName} =~ /^pending/i ) {
            $TicketObject->TicketPendingTimeSet(
                UserID   => $Self->{UserID},
                TicketID => $Self->{TicketID},
                Year     => $GetParam{Year},
                Month    => $GetParam{Month},
                Day      => $GetParam{Day},
                Hour     => $GetParam{Hour},
                Minute   => $GetParam{Minute},
            );
        }

        # log use response id and reply article id (useful for response diagnostics)
        $TicketObject->HistoryAdd(
            Name         => "ResponseTemplate ($GetParam{ResponseID}/$GetParam{ReplyArticleID}/$ArticleID)",
            HistoryType  => 'Misc',
            TicketID     => $Self->{TicketID},
            CreateUserID => $Self->{UserID},
        );

        # remove pre submited attachments
        $UploadCacheObject->FormIDRemove( FormID => $GetParam{FormID} );

        # redirect
        if ( $StateData{TypeName} =~ /^close/i ) {
            return $LayoutObject->PopupClose(
                URL => ( $Self->{LastScreenOverview} || 'Action=AgentDashboard' ),
            );
        }

        # load new URL in parent window and close popup
        return $LayoutObject->PopupClose(
            URL => "Action=AgentTicketZoom;TicketID=$Self->{TicketID};ArticleID=$ArticleID",
        );
    }

    # check for SMIME / PGP if customer has changed
    elsif ( $Self->{Subaction} eq 'AJAXUpdate' ) {

        my @ExtendedData;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' ) {

            # use ticket QueueID in compose modules
            $GetParam{QueueID} = $Ticket{QueueID};

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            JOB:
            for my $Job ( sort keys %Jobs ) {

                # load module
                next JOB if !$MainObject->Require( $Jobs{$Job}->{Module} );

                my $Object = $Jobs{$Job}->{Module}->new(
                    %{$Self},
                    Debug => $Self->{Debug},
                );

                # get params
                for my $Parameter ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter );
                }

                # run module
                my %Data = $Object->Data( %GetParam, Config => $Jobs{$Job} );

                # get AJAX param values
                if ( $Object->can('GetParamAJAX') ) {
                    %GetParam = ( %GetParam, $Object->GetParamAJAX(%GetParam) )
                }

                my $Key = $Object->Option( %GetParam, Config => $Jobs{$Job} );
                if ($Key) {
                    push(
                        @ExtendedData,
                        {
                            Name        => $Key,
                            Data        => \%Data,
                            SelectedID  => $GetParam{$Key},
                            Translation => 1,
                            Max         => 150,
                        }
                    );
                }
            }
        }

        my $NextStates = $Self->_GetNextStates(
            %GetParam,
        );

        # update Dynamc Fields Possible Values via AJAX
        my @DynamicFieldAJAX;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );
            next DYNAMICFIELD if !$IsACLReducible;

            my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                DynamicFieldConfig => $DynamicFieldConfig,
            );

            # convert possible values key => value to key => key for ACLs using a Hash slice
            my %AclData = %{$PossibleValues};
            @AclData{ keys %AclData } = keys %AclData;

            # set possible values filter from ACLs
            my $ACL = $TicketObject->TicketAcl(
                %GetParam,
                Action        => $Self->{Action},
                TicketID      => $Self->{TicketID},
                QueueID       => $Self->{QueueID},
                ReturnType    => 'Ticket',
                ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                Data          => \%AclData,
                UserID        => $Self->{UserID},
            );
            if ($ACL) {
                my %Filter = $TicketObject->TicketAclData();

                # convert Filer key => key back to key => value using map
                %{$PossibleValues} = map { $_ => $PossibleValues->{$_} } keys %Filter;
            }

            my $DataValues = $DynamicFieldBackendObject->BuildSelectionDataGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                PossibleValues     => $PossibleValues,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
            ) || $PossibleValues;

            # add dynamic field to the list of fields to update
            push(
                @DynamicFieldAJAX,
                {
                    Name        => 'DynamicField_' . $DynamicFieldConfig->{Name},
                    Data        => $DataValues,
                    SelectedID  => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                    Translation => $DynamicFieldConfig->{Config}->{TranslatableValues} || 0,
                    Max         => 100,
                }
            );
        }

        my $JSON = $LayoutObject->BuildSelectionJSON(
            [
                @ExtendedData,
                {
                    Name         => 'StateID',
                    Data         => $NextStates,
                    SelectedID   => $GetParam{StateID},
                    Translation  => 1,
                    PossibleNone => 1,
                    Max          => 100,
                },
                @DynamicFieldAJAX,

            ],
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }
    elsif ( $Self->{Subaction} eq 'Preview' ) {
        
        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # get valid state id
        if ( !$GetParam{StateID} ) {
            my %Ticket = $TicketObject->TicketGet(
                TicketID => $Self->{TicketID},
                UserID   => 1,
            );
            $GetParam{StateID} = $Ticket{StateID};
        }

        my %StateData = $Kernel::OM->Get('Kernel::System::State')->StateGet( ID => $GetParam{StateID} );

        my %Error;

        # get check item object
        my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Line . 'ErrorType' } = $Line . $CheckItemObject->CheckErrorType() . 'ServerErrorMsg';
                    $Error{ $Line . 'Invalid' }   = 'ServerError';
                }
                my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
                    Address => $Email->address()
                );
                if ($IsLocal) {
                    $Error{ $Line . 'IsLocalAddress' } = 'ServerError';
                }
            }
        }

        if ( $Error{ToIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'ToIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{CcIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'CcIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        if ( $Error{BccIsLocalAddress} ) {
            $LayoutObject->Block(
                Name => 'BccIsLocalAddressServerErrorMsg',
                Data => \%GetParam,
            );
        }

        # If is an action about attachments
        my $IsUpload = 0;

        # attachment delete
        my @AttachmentIDs = map {
            my ($ID) = $_ =~ m{ \A AttachmentDelete (\d+) \z }xms;
            $ID ? $ID : ();
        } $ParamObject->GetParamNames();

        COUNT:
        for my $Count ( reverse sort @AttachmentIDs ) {
            my $Delete = $ParamObject->GetParam( Param => "AttachmentDelete$Count" );
            next COUNT if !$Delete;
            $Error{AttachmentDelete} = 1;
            $UploadCacheObject->FormIDRemoveFile(
                FormID => $Self->{FormID},
                FileID => $Count,
            );
            $IsUpload = 1;
        }

        # attachment upload
        if ( $ParamObject->GetParam( Param => 'AttachmentUpload' ) ) {
            $IsUpload                = 1;
            %Error                   = ();
            $Error{AttachmentUpload} = 1;
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param => 'FileUpload',
            );
            $UploadCacheObject->FormIDAddFile(
                FormID      => $Self->{FormID},
                Disposition => 'attachment',
                %UploadStuff,
            );
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get time object
        my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

        # check pending date
        if ( $StateData{TypeName} && $StateData{TypeName} =~ /^pending/i ) {
            if ( !$TimeObject->Date2SystemTime( %GetParam, Second => 0 ) ) {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
            if (
                $TimeObject->Date2SystemTime( %GetParam, Second => 0 )
                < $TimeObject->SystemTime()
                )
            {
                if ( !$IsUpload ) {
                    $Error{DateInvalid} = 'ServerError';
                }
            }
        }

        # check if at least one recipient has been chosen
        if ( $IsUpload == 0 ) {
            if ( !$GetParam{To} ) {
                $Error{'ToInvalid'} = 'ServerError';
            }
        }

        # check some values
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$GetParam{$Line};
            for my $Email ( Mail::Address->parse( $GetParam{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    if ( $IsUpload == 0 ) {
                        $Error{ $Line . 'Invalid' } = 'ServerError';
                    }
                }
            }
        }

        # check subject
        if ( !$IsUpload && !$GetParam{Subject} ) {
            $Error{SubjectInvalid} = ' ServerError';
        }

        # check body
        if ( !$IsUpload && !$GetParam{Body} ) {
            $Error{BodyInvalid} = ' ServerError';
        }

        # check time units
        if (
            $ConfigObject->Get('Ticket::Frontend::AccountTime')
            && $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
            && $GetParam{TimeUnits} eq ''
            )
        {
            if ( !$IsUpload ) {
                $Error{TimeUnitsInvalid} = 'ServerError';
            }
        }

        # prepare subject
        my $Tn = $TicketObject->TicketNumberLookup( TicketID => $Self->{TicketID} );
        $GetParam{Subject} = $TicketObject->TicketSubjectBuild(
            TicketNumber => $Tn,
            Subject      => $GetParam{Subject} || '',
        );

        my %ArticleParam;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' )
        {

            # use ticket QueueID in compose modules
            $GetParam{QueueID} = $Ticket{QueueID};

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }
                my $Object = $Jobs{$Job}->{Module}->new( %{$Self}, Debug => $Self->{Debug} );

                # get params
                for ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # ticket params
                %ArticleParam = (
                    %ArticleParam,
                    $Object->ArticleOption( %GetParam, Config => $Jobs{$Job} ),
                );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $PossibleValuesFilter;

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        Action        => $Self->{Action},
                        TicketID      => $Self->{TicketID},
                        ReturnType    => 'Ticket',
                        ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data          => \%AclData,
                        UserID        => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        %{$PossibleValuesFilter} = map { $_ => $PossibleValues->{$_} }
                            keys %Filter;
                    }
                }
            }

            my $ValidationResult;

            # do not validate on attachment upload
            if ( !$IsUpload ) {

                $ValidationResult = $DynamicFieldBackendObject->EditFieldValueValidate(
                    DynamicFieldConfig   => $DynamicFieldConfig,
                    PossibleValuesFilter => $PossibleValuesFilter,
                    ParamObject          => $ParamObject,
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                );

                if ( !IsHashRefWithData($ValidationResult) ) {
                    return $LayoutObject->ErrorScreen(
                        Message =>
                            "Could not perform validation on field $DynamicFieldConfig->{Label}!",
                        Comment => Translatable('Please contact the admin.'),
                    );
                }

                # propagate validation error to the Error variable to be detected by the frontend
                if ( $ValidationResult->{ServerError} ) {
                    $Error{ $DynamicFieldConfig->{Name} } = ' ServerError';
                }
            }

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                PossibleValuesFilter => $PossibleValuesFilter,
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                ServerError  => $ValidationResult->{ServerError}  || '',
                ErrorMessage => $ValidationResult->{ErrorMessage} || '',
                LayoutObject => $LayoutObject,
                ParamObject  => $ParamObject,
                AJAXUpdate   => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # check if there is an error
        if (%Error) {

            my $Output = $LayoutObject->Header(
                Value     => $Ticket{TicketNumber},
                Type      => 'Small',
                BodyClass => 'Popup',
            );
            $GetParam{StandardResponse} = $GetParam{Body};
            $Output .= $Self->_Mask(
                TicketID   => $Self->{TicketID},
                NextStates => $Self->_GetNextStates(
                    %GetParam,
                ),
                ResponseFormat      => $LayoutObject->Ascii2Html( Text => $GetParam{Body} ),
                Errors              => \%Error,
                MultipleCustomer    => \@MultipleCustomer,
                MultipleCustomerCc  => \@MultipleCustomerCc,
                MultipleCustomerBcc => \@MultipleCustomerBcc,
                Attachments         => \@Attachments,
                GetParam            => \%GetParam,
                TicketBackType      => $TicketBackType,
                %Ticket,
                DynamicFieldHTML => \%DynamicFieldHTML,
                %GetParam,
            );
            $Output .= $LayoutObject->Footer(
                Type => 'Small',
            );
            return $Output;
        }

        # replace <OTRS_TICKET_STATE> with next ticket state name
        if ( $StateData{Name} ) {
            $GetParam{Body} =~ s/<OTRS_TICKET_STATE>/$StateData{Name}/g;
            $GetParam{Body} =~ s/&lt;OTRS_TICKET_STATE&gt;/$StateData{Name}/g;
        }

        # get pre loaded attachments
        my @AttachmentData = $UploadCacheObject->FormIDGetAllFilesData(
            FormID => $Self->{FormID},
        );

        # get submit attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );
        if (%UploadStuff) {
            push @AttachmentData, \%UploadStuff;
        }

        # get recipients
        my $Recipients = '';
        LINE:
        for my $Line (qw(To Cc Bcc)) {

            next LINE if !$GetParam{$Line};

            if ($Recipients) {
                $Recipients .= ', ';
            }
            $Recipients .= $GetParam{$Line};
        }

        my $MimeType = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $MimeType = 'text/html';

            # remove unused inline images
            my @NewAttachmentData;
            ATTACHMENT:
            for my $Attachment (@AttachmentData) {
                my $ContentID = $Attachment->{ContentID};
                if (
                    $ContentID
                    && ( $Attachment->{ContentType} =~ /image/i )
                    && ( $Attachment->{Disposition} eq 'inline' )
                    )
                {
                    my $ContentIDHTMLQuote = $LayoutObject->Ascii2Html(
                        Text => $ContentID,
                    );

                    # workaround for link encode of rich text editor, see bug#5053
                    my $ContentIDLinkEncode = $LayoutObject->LinkEncode($ContentID);
                    $GetParam{Body} =~ s/(ContentID=)$ContentIDLinkEncode/$1$ContentID/g;

                    # ignore attachment if not linked in body
                    next ATTACHMENT
                        if $GetParam{Body} !~ /(\Q$ContentIDHTMLQuote\E|\Q$ContentID\E)/i;
                }

                # remember inline images and normal attachments
                push @NewAttachmentData, \%{$Attachment};
            }
            @AttachmentData = @NewAttachmentData;

            # verify HTML document
            $GetParam{Body} = $LayoutObject->RichTextDocumentComplete(
                String => $GetParam{Body},
            );
        }

        # if there is no ArticleTypeID, use the default value
        my $ArticleTypeID = $GetParam{ArticleTypeID} // $TicketObject->ArticleTypeLookup(
            ArticleType => $Config->{DefaultArticleType},
        );

        # error page
        if ( !$ArticleTypeID ) {
            return $LayoutObject->ErrorScreen(
                Comment => Translatable('Can not determine the ArticleType, Please contact the admin.'),
            );
        }
        
        # get template
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
        
        # get salutation
        $GetParam{Salutation} = $TemplateGenerator->Salutation(
            TicketID => $Self->{TicketID},
            Data     => \%GetParam,
            UserID   => $Self->{UserID},
        );

        # get signature
        $GetParam{Signature} = $TemplateGenerator->Signature(
            TicketID => $Self->{TicketID},
            Data     => \%GetParam,
            UserID   => $Self->{UserID},
        );
        
        my $ReplyBody = $Self->_GetReplyBody(
            ArticleTypeID => $ArticleTypeID,
            %DynamicFieldValues,
            %GetParam,
            );
        
        return $LayoutObject->Attachment(
            Type => 'inline',
            Filename => 'preview',
            ContentType => 'text/html',
            Charset => 'UTF-8',
            Content => $ReplyBody,
        );
    }
    else {
        my $Output = $LayoutObject->Header(
            Value     => $Ticket{TicketNumber},
            Type      => 'Small',
            BodyClass => 'Popup',
        );

        # get std attachment object
        my $StdAttachmentObject = $Kernel::OM->Get('Kernel::System::StdAttachment');

        # add std. attachments to email
        if ( $GetParam{ResponseID} ) {
            my %AllStdAttachments = $StdAttachmentObject->StdAttachmentStandardTemplateMemberList(
                StandardTemplateID => $GetParam{ResponseID},
            );
            for ( sort keys %AllStdAttachments ) {
                my %Data = $StdAttachmentObject->StdAttachmentGet( ID => $_ );
                $UploadCacheObject->FormIDAddFile(
                    FormID      => $Self->{FormID},
                    Disposition => 'attachment',
                    %Data,
                );
            }
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get last customer article or selected article ...
        my %Data;
        if ( $GetParam{ArticleID} ) {
            %Data = $TicketObject->ArticleGet(
                ArticleID     => $GetParam{ArticleID},
                DynamicFields => 1,
            );
        }
        else {
            %Data = $TicketObject->ArticleLastCustomerArticle(
                TicketID      => $Self->{TicketID},
                DynamicFields => 1,
            );
        }

        # set OrigFrom for correct email quoting (xxxx wrote)
        $Data{OrigFrom} = $Data{From};

        # check article type and replace To with From (in case)
        if ( $Data{SenderType} !~ /customer/ ) {

            # replace From/To, To/From because sender is agent
            my $To = $Data{To};
            $Data{To}   = $Data{From};
            $Data{From} = $To;

            $Data{ReplyTo} = '';
        }

        # build OrigFromName (to only use the realname)
        $Data{OrigFromName} = $Data{OrigFrom};
        $Data{OrigFromName} =~ s/<.*>|\(.*\)|\"|;|,//g;
        $Data{OrigFromName} =~ s/( $)|(  $)//g;

        # get customer data
        my %Customer;
        if ( $Ticket{CustomerUserID} ) {
            %Customer = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
                User => $Ticket{CustomerUserID}
            );
        }

        # get article to quote
        $Data{Body} = $LayoutObject->ArticleQuote(
            TicketID          => $Self->{TicketID},
            ArticleID         => $Data{ArticleID},
            FormID            => $Self->{FormID},
            UploadCacheObject => $UploadCacheObject,
        );

        # restrict number of body lines if configured
        if (
            $Data{Body}
            && $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines')
            )
        {
            my $MaxLines = $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines');

            # split body - one element per line
            my @Body = split "\n", $Data{Body};

            # only modify if body is longer than allowed
            if ( scalar @Body > $MaxLines ) {

                # splice to max. allowed lines and reassemble
                @Body = @Body[ 0 .. ( $MaxLines - 1 ) ];
                $Data{Body} = join "\n", @Body;
            }
        }

        if ( $LayoutObject->{BrowserRichText} ) {

            # prepare body, subject, ReplyTo ...
            # rewrap body if exists
            if ( $Data{Body} ) {
                $Data{Body} =~ s/\t/ /g;
                my $Quote = $LayoutObject->Ascii2Html(
                    Text => $ConfigObject->Get('Ticket::Frontend::Quote') || '',
                    HTMLResultMode => 1,
                );
                if ($Quote) {

                    # quote text
                    $Data{Body} = "<blockquote type=\"cite\">$Data{Body}</blockquote>\n";

                    # cleanup not compat. tags
                    $Data{Body} = $LayoutObject->RichTextDocumentCleanup(
                        String => $Data{Body},
                    );

                }
                else {
                    $Data{Body} = "<br/>" . $Data{Body};

                    if ( $Data{Created} ) {
                        $Data{Body} = $LayoutObject->{LanguageObject}->Translate('Date') .
                            ": $Data{Created}<br/>" . $Data{Body};
                    }

                    for (qw(Subject ReplyTo Reply-To Cc To From)) {
                        if ( $Data{$_} ) {
                            $Data{Body} = $LayoutObject->{LanguageObject}->Translate($_) .
                                ": $Data{$_}<br/>" . $Data{Body};
                        }
                    }

                    my $From = $LayoutObject->Ascii2RichText(
                        String => $Data{From},
                    );

                    my $MessageFrom = $LayoutObject->{LanguageObject}->Translate('Message from');
                    my $EndMessage  = $LayoutObject->{LanguageObject}->Translate('End message');

                    $Data{Body} = "<br/>---- $MessageFrom $From ---<br/><br/>" . $Data{Body};
                    $Data{Body} .= "<br/>---- $EndMessage ---<br/>";
                }
            }
        }
        else {

            # prepare body, subject, ReplyTo ...
            # rewrap body if exists
            if ( $Data{Body} ) {
                $Data{Body} =~ s/\t/ /g;
                my $Quote = $ConfigObject->Get('Ticket::Frontend::Quote');
                if ($Quote) {
                    $Data{Body} =~ s/\n/\n$Quote /g;
                    $Data{Body} = "\n$Quote " . $Data{Body};
                }
                else {
                    $Data{Body} = "\n" . $Data{Body};
                    if ( $Data{Created} ) {
                        $Data{Body} = $LayoutObject->{LanguageObject}->Translate('Date') .
                            ": $Data{Created}\n" . $Data{Body};
                    }

                    for (qw(Subject ReplyTo Reply-To Cc To From)) {
                        if ( $Data{$_} ) {
                            $Data{Body} = $LayoutObject->{LanguageObject}->Translate($_) .
                                ": $Data{$_}\n" . $Data{Body};
                        }
                    }

                    my $MessageFrom = $LayoutObject->{LanguageObject}->Translate('Message from');
                    my $EndMessage  = $LayoutObject->{LanguageObject}->Translate('End message');

                    $Data{Body} = "\n---- $MessageFrom $Data{From} ---\n\n" . $Data{Body};
                    $Data{Body} .= "\n---- $EndMessage ---\n";
                }
            }
        }

        # get system address object
        my $SystemAddress = $Kernel::OM->Get('Kernel::System::SystemAddress');

        # add not local To addresses to Cc
        for my $Email ( Mail::Address->parse( $Data{To} ) ) {
            my $IsLocal = $SystemAddress->SystemAddressIsLocalAddress(
                Address => $Email->address(),
            );
            if ( !$IsLocal ) {
                if ( $Data{Cc} ) {
                    $Data{Cc} .= ', ';
                }
                $Data{Cc} .= $Email->format();
            }
        }

        # check ReplyTo
        if ( $Data{ReplyTo} ) {
            $Data{To} = $Data{ReplyTo};
        }
        else {
            $Data{To} = $Data{From};

            # try to remove some wrong text to from line (by way of ...)
            # added by some strange mail programs on bounce
            $Data{To} =~ s/(.+?\<.+?\@.+?\>)\s+\(by\s+way\s+of\s+.+?\)/$1/ig;
        }

        # get to email (just "some@example.com")
        for my $Email ( Mail::Address->parse( $Data{To} ) ) {
            $Data{ToEmail} = $Email->address();
        }

        # only reply to sender
        if ( !$GetParam{ReplyAll} ) {
            $Data{Cc}  = '';
            $Data{Bcc} = '';
        }

        # use customer database email
        # do not add customer email to cc, if article type is email-internal
        my $DataArticleType = $TicketObject->ArticleTypeLookup( ArticleTypeID => $Data{ArticleTypeID} );
        if (
            $ConfigObject->Get('Ticket::Frontend::ComposeAddCustomerAddress')
            && $DataArticleType !~ m{internal}
            )
        {

            # check if customer is in recipient list
            if ( $Customer{UserEmail} && $Data{ToEmail} !~ /^\Q$Customer{UserEmail}\E$/i ) {

                if ( $Data{SenderType} eq 'agent' && $DataArticleType !~ m{external} ) {
                    if ( $Data{To} ) {
                        $Data{To} .= ', ' . $Customer{UserEmail};
                    }
                    else {
                        $Data{To} = $Customer{UserEmail};
                    }
                }

                # replace To with customers database address
                elsif ( $ConfigObject->Get('Ticket::Frontend::ComposeReplaceSenderAddress') ) {

                    $Output .= $LayoutObject->Notify(
                        Data => $LayoutObject->{LanguageObject}->Translate(
                            'Address %s replaced with registered customer address.',
                            $Data{ToEmail},
                        ),

                    );
                    $Data{To} = $Customer{UserEmail};
                }

                # add customers database address to Cc
                else {
                    $Output .= $LayoutObject->Notify(
                        Info => Translatable("Customer user automatically added in Cc."),
                    );
                    if ( $Data{Cc} ) {
                        $Data{Cc} .= ', ' . $Customer{UserEmail};
                    }
                    else {
                        $Data{Cc} = $Customer{UserEmail};
                    }
                }
            }
        }

        # find duplicate addresses
        my %Recipient;
        for my $Type (qw(To Cc Bcc)) {
            if ( $Data{$Type} ) {
                my $NewLine = '';
                for my $Email ( Mail::Address->parse( $Data{$Type} ) ) {
                    my $Address = lc $Email->address();

                    # only use email addresses with @ inside
                    if ( $Address && $Address =~ /@/ && !$Recipient{$Address} ) {
                        $Recipient{$Address} = 1;
                        my $IsLocal = $SystemAddress->SystemAddressIsLocalAddress(
                            Address => $Address,
                        );
                        if ( !$IsLocal ) {
                            if ($NewLine) {
                                $NewLine .= ', ';
                            }
                            $NewLine .= $Email->format();
                        }
                    }
                }
                $Data{$Type} = $NewLine;
            }
        }

        # get template
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');

        # use key StdResponse to pass the data to the template for legacy reasons,
        #   because existing systems may have it in their configuration as that was
        #   the key used before the internal switch to StandardResponse And StandardTemplate
        $Data{StdResponse} = $TemplateGenerator->Template(
            TicketID   => $Self->{TicketID},
            ArticleID  => $GetParam{ArticleID},
            TemplateID => $GetParam{ResponseID},
            Data       => \%Data,
            UserID     => $Self->{UserID},
        );

        # get salutation
        $Data{Salutation} = $TemplateGenerator->Salutation(
            TicketID => $Self->{TicketID},
            Data     => \%Data,
            UserID   => $Self->{UserID},
        );

        # get signature
        $Data{Signature} = $TemplateGenerator->Signature(
            TicketID => $Self->{TicketID},
            Data     => \%Data,
            UserID   => $Self->{UserID},
        );

        # $TemplateGenerator->Attributes() does not overwrite %Data, but it adds more keys
        %Data = $TemplateGenerator->Attributes(
            TicketID  => $Self->{TicketID},
            ArticleID => $GetParam{ArticleID},
            Data      => \%Data,
            UserID    => $Self->{UserID},
        );

        my $ResponseFormat = $ConfigObject->Get('Ticket::Frontend::ResponseFormat')
            || '[% Data.Salutation | html %]
[% Data.StdResponse | html %]
[% Data.Signature | html %]

[% Data.Created | Localize("TimeShort") %] - [% Data.OrigFromName | html %] [% Translate("wrote") | html %]:
[% Data.Body | html %]
';

        # make sure body is rich text
        my %DataHTML = %Data;
        if ( $LayoutObject->{BrowserRichText} ) {
            $ResponseFormat = $LayoutObject->Ascii2RichText(
                String => $ResponseFormat,
            );

            # restore qdata formatting for Output replacement
            $ResponseFormat =~ s/&quot;/"/gi;

            # html quote to have it correct in edit area
            $ResponseFormat = $LayoutObject->Ascii2Html(
                Text => $ResponseFormat,
            );

            # restore qdata formatting for Output replacement
            $ResponseFormat =~ s/&quot;/"/gi;

            # quote all non html content to have it correct in edit area
            KEY:
            for my $Key ( sort keys %DataHTML ) {
                next KEY if !$DataHTML{$Key};
                next KEY if $Key eq 'Salutation';
                next KEY if $Key eq 'Body';
                next KEY if $Key eq 'StdResponse';
                next KEY if $Key eq 'Signature';
                $DataHTML{$Key} = $LayoutObject->Ascii2RichText(
                    String => $DataHTML{$Key},
                );
            }
        }

        # build new repsonse format based on template
        $Data{ResponseFormat} = $LayoutObject->Output(
            Template => $ResponseFormat,
            Data     => { %Param, %DataHTML },
        );

        # check some values
        my %Error;
        LINE:
        for my $Line (qw(To Cc Bcc)) {
            next LINE if !$Data{$Line};
            for my $Email ( Mail::Address->parse( $Data{$Line} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Line . "Invalid" } = " ServerError"
                }
            }
        }
        if ( $Data{From} ) {
            for my $Email ( Mail::Address->parse( $Data{From} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{"FromInvalid"} .= $CheckItemObject->CheckError();
                }
            }
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $PossibleValuesFilter;

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        Action        => $Self->{Action},
                        TicketID      => $Self->{TicketID},
                        ReturnType    => 'Ticket',
                        ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data          => \%AclData,
                        UserID        => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        %{$PossibleValuesFilter} = map { $_ => $PossibleValues->{$_} }
                            keys %Filter;
                    }
                }
            }

            # to store dynamic field value from database (or undefined)
            my $Value;

            # only get values for Ticket fields (all screens based on AgentTickeActionCommon
            # generates a new article, then article fields will be always empty at the beginign)
            if ( $DynamicFieldConfig->{ObjectType} eq 'Ticket' ) {

                # get value stored on the database from Ticket
                $Value = $Ticket{ 'DynamicField_' . $DynamicFieldConfig->{Name} };
            }

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                PossibleValuesFilter => $PossibleValuesFilter,
                Value                => $Value,
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                LayoutObject    => $LayoutObject,
                ParamObject     => $ParamObject,
                AJAXUpdate      => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # build references if exist
        my $References = ( $Data{MessageID} || '' ) . ( $Data{References} || '' );

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' )
        {
            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }
                my $Object = $Jobs{$Job}->{Module}->new( %{$Self}, Debug => $Self->{Debug} );

                # get params
                for ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$_} = $ParamObject->GetParam( Param => $_ );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        # build view ...
        $Output .= $Self->_Mask(
            TicketID   => $Self->{TicketID},
            NextStates => $Self->_GetNextStates(
                %GetParam,
            ),
            Attachments         => \@Attachments,
            Errors              => \%Error,
            MultipleCustomer    => \@MultipleCustomer,
            MultipleCustomerCc  => \@MultipleCustomerCc,
            MultipleCustomerBcc => \@MultipleCustomerBcc,
            GetParam            => \%GetParam,
            ResponseID          => $GetParam{ResponseID},
            ReplyArticleID      => $GetParam{ArticleID},
            %Ticket,
            %Data,
            InReplyTo        => $Data{MessageID},
            References       => "$References",
            TicketBackType   => $TicketBackType,
            DynamicFieldHTML => \%DynamicFieldHTML,
        );
        $Output .= $LayoutObject->Footer(
            Type => 'Small',
        );
        return $Output;
    }
}

sub _GetNextStates {
    my ( $Self, %Param ) = @_;

    # get next states
    my %NextStates = $Kernel::OM->Get('Kernel::System::Ticket')->TicketStateList(
        %Param,
        Action   => $Self->{Action},
        TicketID => $Self->{TicketID},
        UserID   => $Self->{UserID},
    );
    return \%NextStates;
}

sub _Mask {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldNames = $Self->_GetFieldsToUpdate(
        OnlyDynamicFields => 1
    );

    # create a string with the quoted dynamic field names separated by commas
    if ( IsArrayRefWithData($DynamicFieldNames) ) {
        FIELD:
        for my $Field ( @{$DynamicFieldNames} ) {
            $Param{DynamicFieldNamesStrg} .= ", '" . $Field . "'";
        }
    }

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get config for frontend module
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    my %State;
    if ( $Param{GetParam}->{StateID} ) {
        $State{SelectedID} = $Param{GetParam}->{StateID};
    }
    else {
        $State{SelectedValue} = $Config->{StateDefault};
    }
    $Param{NextStatesStrg} = $LayoutObject->BuildSelection(
        Data         => $Param{NextStates},
        Name         => 'StateID',
        PossibleNone => 1,
        %State,
        %Param,
        Class => 'Modernize',
    );

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    #  get article type
    my %ArticleTypeList;

    if ( $Config->{ArticleTypes} ) {

        my @ArticleTypesPossible = @{ $Config->{ArticleTypes} };
        for my $ArticleTypeID (@ArticleTypesPossible) {
            my $ArticleType = $TicketObject->ArticleTypeLookup(
                ArticleType => $ArticleTypeID,
            );
            $ArticleTypeList{$ArticleType} = $ArticleTypeID;
        }

        my %Selected;
        if ( $Self->{GetParam}->{ArticleTypeID} ) {
            $Selected{SelectedID} = $Self->{GetParam}->{ArticleTypeID};
        }
        else {
            $Selected{SelectedValue} = $Config->{DefaultArticleType};
        }

        $Param{ArticleTypesStrg} = $LayoutObject->BuildSelection(
            Data => \%ArticleTypeList,
            Name => 'ArticleTypeID',
            %Selected,
            Class => 'Modernize',
        );

        $LayoutObject->Block(
            Name => 'ArticleType',
            Data => \%Param,
        );
    }

    # build customer search auto-complete field
    $LayoutObject->Block(
        Name => 'CustomerSearchAutoComplete',
    );

    # prepare errors!
    if ( $Param{Errors} ) {
        for my $Error ( sort keys %{ $Param{Errors} } ) {
            $Param{$Error} = $LayoutObject->Ascii2Html(
                Text => $Param{Errors}->{$Error},
            );
        }
    }

    # get used calendar
    my $Calendar = $TicketObject->TicketCalendarGet(
        QueueID => $Param{QueueID},
        SLAID   => $Param{SLAID},
    );

    # pending data string
    $Param{PendingDateString} = $LayoutObject->BuildDateSelection(
        %Param,
        Format               => 'DateInputFormatLong',
        YearPeriodPast       => 0,
        YearPeriodFuture     => 5,
        DiffTime             => $ConfigObject->Get('Ticket::Frontend::PendingDiffTime') || 0,
        Class                => $Param{Errors}->{DateInvalid} || ' ',
        Validate             => 1,
        ValidateDateInFuture => 1,
        Calendar             => $Calendar,
    );

    # Multiple-Autocomplete
    $Param{To} = ( scalar @{ $Param{MultipleCustomer} } ? '' : $Param{To} );
    if ( defined $Param{To} && $Param{To} ne '' ) {
        $Param{ToInvalid} = ''
    }

    $Param{Cc} = ( scalar @{ $Param{MultipleCustomerCc} } ? '' : $Param{Cc} );
    if ( defined $Param{Cc} && $Param{Cc} ne '' ) {
        $Param{CcInvalid} = ''
    }

    # Cc
    my $CustomerCounterCc = 0;
    if ( $Param{MultipleCustomerCc} ) {
        for my $Item ( @{ $Param{MultipleCustomerCc} } ) {
            $LayoutObject->Block(
                Name => 'CcMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Cc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CcCustomerErrorExplantion',
                );
            }
            $CustomerCounterCc++;
        }
    }

    if ( !$CustomerCounterCc ) {
        $Param{CcCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'CcMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterCc,
        },
    );

    # Bcc
    my $CustomerCounterBcc = 0;
    if ( $Param{MultipleCustomerBcc} ) {
        for my $Item ( @{ $Param{MultipleCustomerBcc} } ) {
            $LayoutObject->Block(
                Name => 'BccMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Bcc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'BccCustomerErrorExplantion',
                );
            }
            $CustomerCounterBcc++;
        }
    }

    if ( !$CustomerCounterBcc ) {
        $Param{BccCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'BccMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterBcc++,
        },
    );

    # To
    my $CustomerCounter = 0;
    if ( $Param{MultipleCustomer} ) {
        for my $Item ( @{ $Param{MultipleCustomer} } ) {
            $LayoutObject->Block(
                Name => 'MultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CustomerErrorExplantion',
                );
            }
            $CustomerCounter++;
        }
    }

    if ( !$CustomerCounter ) {
        $Param{CustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'MultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounter,
        },
    );

    if ( $Param{ToInvalid} && $Param{Errors} ) {
        $LayoutObject->Block(
            Name => 'ToServerErrorMsg',
        );
    }

    # set preselected values for Cc field
    if ( $Param{Cc} && $Param{Cc} ne '' && !$CustomerCounterCc ) {
        $LayoutObject->Block(
            Name => 'PreFilledCc',
        );

        # split To values
        for my $Email ( Mail::Address->parse( $Param{Cc} ) ) {
            $LayoutObject->Block(
                Name => 'PreFilledCcRow',
                Data => {
                    Email => $Email->address(),
                },
            );
        }
        $Param{Cc} = '';
    }

    # set preselected values for To field
    if ( $Param{To} ne '' && !$CustomerCounter ) {
        $LayoutObject->Block(
            Name => 'PreFilledTo',
        );

        # split To values
        for my $Email ( Mail::Address->parse( $Param{To} ) ) {
            $LayoutObject->Block(
                Name => 'PreFilledToRow',
                Data => {
                    Email => $Email->address(),
                },
            );
        }
        $Param{To} = '';
    }

    $LayoutObject->Block(
        Name => $Param{TicketBackType},
        Data => {

            #            FormID => $Self->{FormID},
            %Param,
        },
    );

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # Dynamic fields
    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # skip fields that HTML could not be retrieved
        next DYNAMICFIELD if !IsHashRefWithData(
            $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} }
        );

        # get the html strings form $Param
        my $DynamicFieldHTML = $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} };

        $LayoutObject->Block(
            Name => 'DynamicField',
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );

        # example of dynamic fields order customization
        $LayoutObject->Block(
            Name => 'DynamicField_' . $DynamicFieldConfig->{Name},
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }

    # show time accounting box
    if ( $ConfigObject->Get('Ticket::Frontend::AccountTime') ) {
        if ( $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime') ) {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabelMandatory',
                Data => \%Param,
            );
            $Param{TimeUnitsRequired} = 'Validate_Required';
        }
        else {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabel',
                Data => \%Param,
            );
            $Param{TimeUnitsRequired} = '';
        }
        $LayoutObject->Block(
            Name => 'TimeUnits',
            Data => \%Param,
        );
    }

    my $ShownOptionsBlock;

    # show spell check
    if ( $LayoutObject->{BrowserSpellChecker} ) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {},
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'SpellCheck',
            Data => {},
        );
    }

    # show address book
    if ( $LayoutObject->{BrowserJavaScriptSupport} ) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {},
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'AddressBook',
            Data => {},
        );
    }

    # add rich text editor
    if ( $LayoutObject->{BrowserRichText} ) {

        # use height/width defined for this screen
        $Param{RichTextHeight} = $Config->{RichTextHeight} || 0;
        $Param{RichTextWidth}  = $Config->{RichTextWidth}  || 0;

        $LayoutObject->Block(
            Name => 'RichText',
            Data => \%Param,
        );
    }

    # show attachments
    ATTACHMENT:
    for my $Attachment ( @{ $Param{Attachments} } ) {
        if (
            $Attachment->{ContentID}
            && $LayoutObject->{BrowserRichText}
            && ( $Attachment->{ContentType} =~ /image/i )
            && ( $Attachment->{Disposition} eq 'inline' )
            )
        {
            next ATTACHMENT;
        }
        $LayoutObject->Block(
            Name => 'Attachment',
            Data => $Attachment,
        );
    }

    # create & return output
    return $LayoutObject->Output(
        TemplateFile => 'AgentTicketCompose',
        Data         => {
            FormID => $Self->{FormID},
            %Param,
        },
    );
}

sub _GetFieldsToUpdate {
    my ( $Self, %Param ) = @_;

    my @UpdatableFields;

    # set the fields that can be updatable via AJAXUpdate
    if ( !$Param{OnlyDynamicFields} ) {
        @UpdatableFields = qw( StateID );
    }

    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $IsACLReducible = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->HasBehavior(
            DynamicFieldConfig => $DynamicFieldConfig,
            Behavior           => 'IsACLReducible',
        );
        next DYNAMICFIELD if !$IsACLReducible;

        push @UpdatableFields, 'DynamicField_' . $DynamicFieldConfig->{Name};
    }

    return \@UpdatableFields;
}

sub _GetReplyBody {
    my ($Self, %Param) = @_;
    
    my $ReplyBody = $Param{Body};
    
    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    
    # $ReplyBody is an html doc, we need to extract only body
    if ($ReplyBody =~ /^.*<body[^>]*>(.*)<\/body>.*$/s) {
        $ReplyBody = $1;
    }
    
    my $Rationale = '';
    if ( defined $Param{Rationale} ) {
        $Rationale = $Param{Rationale};
    }
    
    my $SelectedDocumentsText = '';
    if ( defined $Param{SelectedDocumentsText} ) {
        $SelectedDocumentsText = $Param{SelectedDocumentsText};
        $SelectedDocumentsText = join( '<br/>', split( "\n", $SelectedDocumentsText ) );
    }
    
    # if left unchanged will throw exception
    my $QuestionText = decode('UTF-8', 'Ваш вопрос:');
    my $ReplyText = decode('UTF-8', 'Ответ:');
    my $RationaleText = decode('UTF-8', 'Обоснование:');
    
    # get last customer article or selected article ...
    my %Data;
    if ( $Param{ReplyArticleID} ) {
        %Data = $TicketObject->ArticleGet(
            ArticleID     => $Param{ReplyArticleID},
            DynamicFields => 1,
        );
    }
    else {
        %Data = $TicketObject->ArticleLastCustomerArticle(
            TicketID      => $Self->{TicketID},
            DynamicFields => 1,
        );
    }

    # get article to quote
    $Data{Body} = $LayoutObject->ArticleQuote(
        TicketID          => $Self->{TicketID},
        ArticleID         => $Data{ArticleID},
        FormID            => $Self->{FormID},
        UploadCacheObject => $UploadCacheObject,
    );
    
    # restrict number of body lines if configured
    if (
        $Data{Body}
        && $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines')
        )
    {
        my $MaxLines = $ConfigObject->Get('Ticket::Frontend::ResponseQuoteMaxLines');

        # split body - one element per line
        my @Body = split "\n", $Data{Body};

        # only modify if body is longer than allowed
        if ( scalar @Body > $MaxLines ) {

            # splice to max. allowed lines and reassemble
            @Body = @Body[ 0 .. ( $MaxLines - 1 ) ];
            $Data{Body} = join "\n", @Body;
        }
    }

    my $QuestionBody = $Data{Body};
    
    # terrible, horrible, absoutely disgusting workaround
    # until simpler way to store pics is implemented
    $ReplyBody = <<"EOF";
<table width="638" align="center">
<tbody>
    <tr>
        <td align="left">$Param{Salutation}</td>
        <td align="right"><img height="128" src="data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAlgCWAAD/4RD6RXhpZgAATU0AKgAAAAgABAE7AAIAAAAQAAAISodpAAQAAAABAAAIWpydAAEAAAAgAAAQ0uocAAcAAAgMAAAAPgAAAAAc6gAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGVsZW5hIHNodWd1cm92YQAABZADAAIAAAAUAAAQqJAEAAIAAAAUAAAQvJKRAAIAAAADNDQAAJKSAAIAAAADNDQAAOocAAcAAAgMAAAInAAAAAAc6gAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADIwMTU6MDg6MTcgMDk6MDA6NDIAMjAxNTowODoxNyAwOTowMDo0MgAAAGUAbABlAG4AYQAgAHMAaAB1AGcAdQByAG8AdgBhAAAA/+ELImh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8APD94cGFja2V0IGJlZ2luPSfvu78nIGlkPSdXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQnPz4NCjx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iPjxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+PHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9InV1aWQ6ZmFmNWJkZDUtYmEzZC0xMWRhLWFkMzEtZDMzZDc1MTgyZjFiIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iLz48cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0idXVpZDpmYWY1YmRkNS1iYTNkLTExZGEtYWQzMS1kMzNkNzUxODJmMWIiIHhtbG5zOnhtcD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wLyI+PHhtcDpDcmVhdGVEYXRlPjIwMTUtMDgtMTdUMDk6MDA6NDIuNDM3PC94bXA6Q3JlYXRlRGF0ZT48L3JkZjpEZXNjcmlwdGlvbj48cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0idXVpZDpmYWY1YmRkNS1iYTNkLTExZGEtYWQzMS1kMzNkNzUxODJmMWIiIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmNyZWF0b3I+PHJkZjpTZXEgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj48cmRmOmxpPmVsZW5hIHNodWd1cm92YTwvcmRmOmxpPjwvcmRmOlNlcT4NCgkJCTwvZGM6Y3JlYXRvcj48L3JkZjpEZXNjcmlwdGlvbj48L3JkZjpSREY+PC94OnhtcG1ldGE+DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDw/eHBhY2tldCBlbmQ9J3cnPz7/2wBDAAIBAQIBAQICAgICAgICAwUDAwMDAwYEBAMFBwYHBwcGBwcICQsJCAgKCAcHCg0KCgsMDAwMBwkODw0MDgsMDAz/2wBDAQICAgMDAwYDAwYMCAcIDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAz/wAARCAJOAk4DASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9/KKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoooo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RXbdfc7o+L7f/gl5rTXO2XxXpsUX95bN2b8gw/8AQq9T+D//AAT+8JfDW+ivtTkm8SahCd0ZukCW8beoiHX/AIEWr3tstgEZH1oAyCAQCK8XKfCrhjL6yxFHDJyjtzNy/Btr8D1Mx49zzGUvY1a9ovskvxWo9EEahVAAFLjtjigdBRX6IlZWR8fcKKKKYBRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABR+FFFABRgeg5oooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q==" width="128" /></td>
    </tr>
  </tbody>
</table>
<table width="638" border="1" cellspacing="0" cellpadding="10" align="center">
<tbody>
    <tr>
        <td valign="top">
            <p>
                <strong>$QuestionText</strong>
            </p>
            <p>
                $QuestionBody
            <p>
        </td>
    </tr>
    <tr>
        <td valign="top">
            <p>
                <strong>$ReplyText</strong>
            </p>
            <p>
                $ReplyBody
            <p>
        </td>
    </tr>
EOF
    if ($Rationale ne '') {
    $ReplyBody .= <<"EOF";
    <tr>
        <td valign="top">
            <p>
                <strong>$RationaleText</strong>
            </p>
            <p>
                $Rationale
            <p>
        </td>
    </tr>
EOF
    }
    $ReplyBody .= <<"EOF";
</tbody>
</table>
<table width="638" align="center">
<tbody>
EOF
    if ($SelectedDocumentsText ne '') {
    $ReplyBody .= <<"EOF";
    <tr>
        <br/><div>$SelectedDocumentsText</div><br/>
    </tr>
EOF
    }
    $ReplyBody .= <<"EOF";
    <tr>
        <td>$Param{Signature}</td><br/>
    </tr>
</tbody>
</table>

EOF

    $ReplyBody = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->RichTextDocumentComplete(
        String => $ReplyBody,
    );
    
    $ReplyBody =~ s/(\r\n|\n\r)/\n/g;
    $ReplyBody =~ s/\r/\n/g;
    
    return $ReplyBody;
}

1;
