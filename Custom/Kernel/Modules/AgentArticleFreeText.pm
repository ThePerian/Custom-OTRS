# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentArticleFreeText;

use strict;
use warnings;

use Kernel::System::EmailParser;
use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get ticket and article whom fields we must show and update
    my $TicketID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'TicketID' ) || "";
    my $ArticleID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'ArticleID' ) || "";

    # check if Article exists and really belongs to the ticket
    my %ArticleContent;
    my @Adresses;
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    if (!$ArticleID) {
        return $LayoutObject->ErrorScreen(
            Message => 'No ArticleID is given!',
            Comment => 'Please contact the admin.',
        );
    }
    if (!$TicketID) {
        return $LayoutObject->ErrorScreen(
            Message => 'No TicketID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    $Self->{ArticleID} = $ArticleID;
    $Self->{TicketID} = $TicketID;

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

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    # check needed stuff
    if ( !$Self->{TicketID} ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No TicketID is given!',
            Comment => 'Please contact the admin.',
        );
    }
    if ( !$Self->{ArticleID} ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No ArticleID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    # get config of frontend module
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

    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 1,
    );
    my %Article = $TicketObject->ArticleGet(
        ArticleID     => $Self->{ArticleID},
        DynamicFields => 1,
        UserID        => $Self->{UserID},
    );

    $LayoutObject->Block(
        Name => 'Properties',
        Data => {
            FormID         => $Self->{FormID},
            ArticleID => $Self->{ArticleID},
            %Ticket,
            %Article,
            %Param,
        },
    );

    # show right header
    $LayoutObject->Block(
        Name => 'Header' . $Self->{Action},
        Data => {
            ArticleNumber => $Self->{ArticleID},
            %Ticket,
        },
    );
    
    $LayoutObject->Block(
        Name => 'ArticleBack',
        Data => {
            %Param,
            %Ticket,
        },
    );

    # get params
    my %GetParam;
    for my $Key ( qw(Subject ArticleTypeID) ) {
        $GetParam{$Key} = $ParamObject->GetParam( Param => $Key ) || '';
    }

    # get dynamic field values form http request
    my %DynamicFieldValues;

    # define the dynamic fields to show based on the object type
    my $ObjectType = ['Article'];

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => $ObjectType,
        FieldFilter => $Config->{DynamicField} || {},
    );

    # get dynamic field backend object
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # cycle trough the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicField} ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value form the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
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

    # get upload cache object
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');

    if ( $Self->{Subaction} eq 'Store' ) {
        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # store action
        my %Error;
            
        # check subject
        if ( $Config->{Subject} && !$GetParam{Subject} ) {
            $Error{'SubjectInvalid'} = 'ServerError';
        }

        # check type
        if (
            ( $ConfigObject->Get('Article::Type') )
            &&
            ( $Config->{ArticleType} )
            &&
            ( !$GetParam{ArticleTypeID} )
           )
        {
            $Error{'TypeIDInvalid'} = ' ServerError';
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
                        ReturnType    => 'Article',
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
                    Comment => 'Please contact the admin.',
                );
            }

            # propagate validation error to the Error variable to be detected by the frontend
            if ( $ValidationResult->{ServerError} ) {
                $Error{ $DynamicFieldConfig->{Name} } = ' ServerError';
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
                AJAXUpdate   => 0,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # check errors
        if (%Error) {

            my $Output = $LayoutObject->Header(
                Type      => 'Small',
                Value     => $Self->{ArticleID},
                BodyClass => 'Popup',
            );
            $Output .= $Self->_Mask(
                %Ticket,
                %Article,
                DynamicFieldHTML => \%DynamicFieldHTML,
                %GetParam,
                %Error,
            );
            $Output .= $LayoutObject->Footer(
                Type => 'Small',
            );
            return $Output;
        }

        if ( !$GetParam{Subject} ) {
            $GetParam{Subject} = $GetParam{Subject}
                || $LayoutObject->{LanguageObject}->Translate('No subject');
        }

        # set new subject
        if ( $Config->{Subject} ) {
            if ( defined $GetParam{Subject} ) {
                $TicketObject->ArticleUpdate(
                    Key      => 'Subject',
                    Value    => $GetParam{Subject},
                    ArticleID => $Self->{ArticleID},
                    TicketID => $Self->{TicketID},
                    UserID   => $Self->{UserID},
                );
            }
        }

        # if there is no ArticleTypeID, use the default value
        if ( !defined $GetParam{ArticleTypeID} ) {
            $GetParam{ArticleType} = $Config->{ArticleTypeDefault};
        }

        # set new type
        if ( $Config->{ArticleType} ) {
            if ( $GetParam{ArticleTypeID} ) {
                my %ArticleList = $TicketObject->ArticleTypeList(
                    Result => 'HASH',
                );
                $TicketObject->ArticleUpdate(
                    Key      => 'ArticleType',
                    Value    => $ArticleList{$GetParam{ArticleTypeID}},
                    ArticleID => $Self->{ArticleID},
                    TicketID => $Self->{TicketID},
                    UserID   => $Self->{UserID},
                );
            }
        }

        # set dynamic fields
        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicField} ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            # set the object ID (TicketID or ArticleID) depending on the field configration
            my $ObjectID = $DynamicFieldConfig->{ObjectType} eq 'Article' ? $Self->{ArticleID} : $Self->{TicketID};

            # set the value
            my $Success = $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $ObjectID,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                UserID             => $Self->{UserID},
            );
        }

###########################################################################################################
    # send http request with updated info
    $TicketObject->_SendUpdateRequest( TicketID => $Self->{TicketID} );
###########################################################################################################

        # load new URL in parent window and close popup
        my $ReturnURL = "Action=AgentTicketZoom;TicketID=$Self->{TicketID};ArticleID=$Self->{ArticleID}";

        return $LayoutObject->PopupClose(
            URL => $ReturnURL,
        );
    }
    else {
        if ( !defined $GetParam{Subject} && $Config->{Subject} ) {
            $GetParam{Subject} = $LayoutObject->Output(
                Template => $Config->{Subject},
            );
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
                        ReturnType    => 'Article',
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
            my $Value = $Article{ 'DynamicField_' . $DynamicFieldConfig->{Name} };

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
                AJAXUpdate      => 0,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
                );
        }

        # print form ...
        my $Output = $LayoutObject->Header(
            Type      => 'Small',
            Value     => $Self->{ArticleID},
            BodyClass => 'Popup',
        );
        $Output .= $Self->_Mask(
            %GetParam,
            %Ticket,
            %Article,
            DynamicFieldHTML => \%DynamicFieldHTML,
        );
        $Output .= $LayoutObject->Footer(
            Type => 'Small',
        );
        return $Output;
    }
}

sub _Mask {
    my ( $Self, %Param ) = @_;

    for my $Key ( keys %Param ) {
        if ( !defined $Param{$Key} ) {
            $Param{$Key} = '';
        }
    }

    # get list type
    my $TreeView = 0;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    if ( $ConfigObject->Get('Ticket::Frontend::ListType') eq 'tree' ) {
        $TreeView = 1;
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 1,
    );
    
    my %Article = $TicketObject->ArticleGet(
        ArticleID     => $Self->{ArticleID},
        DynamicFields => 1,
        UserID        => $Self->{UserID},
    );

    # get config of frontend module
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # Widget Ticket Actions
    if (
        $Config->{ArticleType} ||
        $Config->{Subject}
        )
    {
        $LayoutObject->Block(
            Name => 'WidgetArticleActions',
        );
    }

    if ( $Config->{Subject} ) {
        $LayoutObject->Block(
            Name => 'Subject',
            Data => \%Param,
        );
    }

    my $DynamicFieldNames = $Self->_GetFieldsToUpdate(
        OnlyDynamicFields => 1,
    );

    # create a string with the quoted dynamic field names separated by commas
    if ( IsArrayRefWithData($DynamicFieldNames) ) {
        for my $Field ( @{$DynamicFieldNames} ) {
            $Param{DynamicFieldNamesStrg} .= ", '" . $Field . "'";
        }
    }

    # types
    if ( $Config->{ArticleType} ) {
        my %ArticleTypes = reverse $TicketObject->ArticleTypeList(
            Result => 'HASH',
        );
        my %Type;
        for my $Key ( keys $Config->{ArticleTypes} ) {
            if ( $Config->{ArticleTypes}->{$Key} eq 1 ) {
                $Type{$ArticleTypes{$Key}} = $Key;
            }
        }
        $Param{TypeStrg} = $LayoutObject->BuildSelection(
            Class => 'Validate_Required Modernize ' . ( $Param{Errors}->{TypeIDInvalid} || ' ' ),
            Data  => \%Type,
            Name  => 'ArticleTypeID',
            SelectedID   => $Param{ArticleTypeID},
            PossibleNone => 1,
            Sort         => 'AlphanumericValue',
            Translation  => 0,
        );
        $LayoutObject->Block(
            Name => 'Type',
            Data => {%Param},
        );
    }

    # End Widget Ticket Actions

    # define the dynamic fields to show based on the object type
    my $ObjectType = ['Article'];

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => $ObjectType,
        FieldFilter => $Config->{DynamicField} || {},
    );

    # Widget Dynamic Fields
    if ( IsArrayRefWithData($DynamicField) ) {
        $LayoutObject->Block(
            Name => 'WidgetDynamicFields',
        );
    }

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

    # End Widget Dynamic Fields

    # get output back
    return $LayoutObject->Output(
        TemplateFile => $Self->{Action},
        Data         => \%Param
    );
}

sub _GetFieldsToUpdate {
    my ( $Self, %Param ) = @_;

    my @UpdatableFields;

    # set the fields that can be updateable via AJAXUpdate
    if ( !$Param{OnlyDynamicFields} ) {
        @UpdatableFields = qw( ArticleTypeID );
    }

    # define the dynamic fields to show based on the object type
    my $ObjectType = ['Article'];

    # get config of frontend module
    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => $ObjectType,
        FieldFilter => $Config->{DynamicField} || {},
    );

    # cycle through the activated Dynamic Fields for this screen
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

1;
