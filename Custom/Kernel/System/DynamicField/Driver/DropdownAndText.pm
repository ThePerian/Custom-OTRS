# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DynamicField::Driver::DropdownAndText;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::DynamicField::Driver::BaseSelect);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Main',
);

=head1 NAME

Kernel::System::DynamicField::Driver::DropdownAndText

=head1 SYNOPSIS

DynamicFields DropdownAndText Driver delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::DynamicField::Backend->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 1,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 1,
        'IsFiltrable'                  => 1,
        'IsStatsCondition'             => 1,
        'IsCustomerInterfaceCapable'   => 1,
    };

    # get the Dynamic Field Backend custom extensions
    my $DynamicFieldDriverExtensions
        = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Extension::Driver::DropdownAndText');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if (
                !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} )
                )
            {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behaviors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $DFValue = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    # extract real values
    my @ReturnData;
    my %Split;
    for my $Item ( @{$DFValue} ) {
        # should not work when split yields one item, but works anyway >_>
        %Split = split(/###/, $Item->{ValueText});
        # presumably working version, but does not work, instead overwrites other 'dropdownandtext's
        # $Split{$split[0]} = $split[1] || '';
        push @ReturnData, {%Split};
    }

    return \@ReturnData;
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    # check for valid possible values list
    if ( !$Param{DynamicFieldConfig}->{Config}->{PossibleValues} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need PossibleValues in DynamicFieldConfig!",
        );
        return;
    }

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }
    
    # get dynamic field value object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    my $Success;
    if ( IsArrayRefWithData( \@Values ) ) {

        # if there is at least one value to set, this means at least one value is selected,
        #    set those values!
        my @ValueText;
        for my $Item (@Values) {
            push @ValueText, { ValueText => (keys %{$Item})[0].'###'.(values %{$Item})[0] };
        }

        $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => \@ValueText,
            UserID   => $Param{UserID},
        );
    }
    else {

        # otherwise no value was selected, then in fact this means that any value there should be
        # deleted
        $Success = $DynamicFieldValueObject->ValueDelete(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            UserID   => $Param{UserID},
        );
    }

    return $Success;
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( IsArrayRefWithData( $Param{Value} ) ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    # get dynamic field value object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    my $Success;
    for my $Item (@Values) {

        $Success = $DynamicFieldValueObject->ValueValidate(
            Value => {
                ValueText => $Item->[0],
            },
            UserID => $Param{UserID}
        );

        return if !$Success
    }

    return $Success;
}

sub SearchSQLGet {
    my ( $Self, %Param ) = @_;

    my %Operators = (
        Equals            => '=',
        GreaterThan       => '>',
        GreaterThanEquals => '>=',
        SmallerThan       => '<',
        SmallerThanEquals => '<=',
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if ( $Operators{ $Param{Operator} } ) {
        my $SQL = " $Param{TableAlias}.value_text $Operators{$Param{Operator}} '";
        $SQL .= $DBObject->Quote( $Param{SearchTerm} ) . "' ";
        return $SQL;
    }

    if ( $Param{Operator} eq 'Like' ) {

        my $SQL = $DBObject->QueryCondition(
            Key   => "$Param{TableAlias}.value_text",
            Value => $Param{SearchTerm},
        );

        return $SQL;
    }

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        'Priority' => 'error',
        'Message'  => "Unsupported Operator $Param{Operator}",
    );

    return;
}

sub SearchSQLOrderFieldGet {
    my ( $Self, %Param ) = @_;

    return "$Param{TableAlias}.value_text";
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldNameSelect = $FieldName.'_Select';
    my $FieldNameInput = $FieldName.'_Input';
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value;
    my @Values;
    my $ValueSelect;
    my $ValueInput;

    # set the field value or default
    if ( $Param{UseDefaultValue} ) {
        $Value = ( defined $FieldConfig->{DefaultValue} ? $FieldConfig->{DefaultValue} : '' );
    }
    $Value = $Param{Value} // $Value;

    # check if a value in a template (GenericAgent etc.)
    # is configured for this dynamic field
    if (
        IsHashRefWithData( $Param{Template} )
        && defined $Param{Template}->{$FieldName}
        )
    {
        $Value = $Param{Template}->{$FieldName};
    }

    # extract the dynamic field values form the web request
    my $FieldValue = $Self->EditFieldValueGet(
        %Param,
    );

    # set value from ParamObject if present
    if ( IsArrayRefWithData($FieldValue) ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldText Modernize';
    if ( defined $Param{Class} && $Param{Class} ne '' ) {
        $FieldClass .= ' ' . $Param{Class};
    }

    # set field as mandatory
    if ( $Param{Mandatory} ) {
        $FieldClass .= ' Validate_Required';
    }

    # set error css class
    if ( $Param{ServerError} ) {
        $FieldClass .= ' ServerError';
    }

    # set TreeView class
    if ( $FieldConfig->{TreeView} ) {
        $FieldClass .= ' DynamicFieldWithTreeView';
    }
    
    # make updatable
    $FieldClass .= ' AJAXUpdatable';

    # set PossibleValues, use PossibleValuesFilter if defined
    my $PossibleValues = $Param{PossibleValuesFilter} // $Self->PossibleValuesGet(%Param);

    my $Size = 1;

    # TODO change ConfirmationNeeded parameter name to something more generic

    # when ConfimationNeeded parameter is present (AdminGenericAgent) the filed should be displayed
    # as an open list, because you might not want to change the value, otherwise a value will be
    # selected
    if ( $Param{ConfirmationNeeded} ) {
        $Size = 5;
    }

    # prepare variables to create HTML strings
    my $HTMLString = '';
    my $DataValues;
    my $HTMLDropdown;
    my $HTMLText;
    my $CurrentFieldNameSelect;
    my $CurrentFieldNameInput;
    my $Index = 0;

    # check value and create HTML string
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            for my $Item ( @{ $Value } ) {
                $Index++;
                $ValueSelect = ( keys %{$Item})[0] || '';
                $ValueInput = (values %{$Item})[0] || '';
                $CurrentFieldNameSelect = $FieldNameSelect . "_$Index";
                $CurrentFieldNameInput = $FieldNameInput . "_$Index";

                $DataValues = $Self->BuildSelectionDataGet(
                    DynamicFieldConfig => $Param{DynamicFieldConfig},
                    PossibleValues     => $PossibleValues,
                    Value              => $ValueSelect,
                );

                $HTMLDropdown = $Param{LayoutObject}->BuildSelection(
                    Data => $DataValues || {},
                    Name => $CurrentFieldNameSelect,
                    SelectedID  => $ValueSelect,
                    Translation => $FieldConfig->{TranslatableValues} || 0,
                    Class       => "$FieldClass DFSelectedDocumentsSelect",
                    Size        => $Size,
                    HTMLQuote   => 1,
                );
                
                my $FieldSelector = '#' . $CurrentFieldNameSelect;

                my $FieldsToUpdate = '';
                if ( IsArrayRefWithData( $Param{UpdatableFields} ) ) {

                    # Remove current field from updatable fields list
                    my @FieldsToUpdate = grep { $_ ne $FieldName } @{ $Param{UpdatableFields} };

                    # quote all fields, put commas in between them
                    $FieldsToUpdate = join( ', ', map {"'$_'"} @FieldsToUpdate );
                }
                
                $HTMLText = <<"EOF";

<input type="text" class="$FieldClass" id="$CurrentFieldNameInput" name="$CurrentFieldNameInput" value="$ValueInput" />
EOF
                
                $HTMLString .= <<"EOF";
                
<div class="ValueRow">
    $HTMLDropdown
    <div id="${CurrentFieldNameSelect}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
    <div id="${CurrentFieldNameSelect}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

    $HTMLText
    <div id="${CurrentFieldNameInput}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
    <div id="${CurrentFieldNameInput}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

    <a href="#" id="RemoveValue_$Index" class="RemoveButton ValueRemove"><i class="fa fa-minus-square-o"></i><span class="InvisibleText">Remove value</span></a>
    <div class="SpacingTopMini" ></div>
</div>
EOF
            }
        }
        else {
            $Index++;
            $ValueSelect = $Value || '';
            $ValueInput = '';
            $CurrentFieldNameSelect = $FieldNameSelect . "_$Index";
            $CurrentFieldNameInput = $FieldNameInput . "_$Index";

            $DataValues = $Self->BuildSelectionDataGet(
                DynamicFieldConfig => $Param{DynamicFieldConfig},
                PossibleValues     => $PossibleValues,
                Value              => $ValueSelect,
            );

            $HTMLDropdown = $Param{LayoutObject}->BuildSelection(
                Data => $DataValues || {},
                Name => $CurrentFieldNameSelect,
                SelectedID  => $ValueSelect,
                Translation => $FieldConfig->{TranslatableValues} || 0,
                Class       => "$FieldClass DFSelectedDocumentsSelect",
                Size        => $Size,
                HTMLQuote   => 1,
            );
            
            $HTMLText = <<"EOF";

<input type="text" class="$FieldClass" id="$CurrentFieldNameInput" name="$CurrentFieldNameInput" value="$ValueInput" />
EOF
            
            $HTMLString .= <<"EOF";
            
<div class="ValueRow">
    $HTMLDropdown
    <div id="${CurrentFieldNameSelect}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
    <div id="${CurrentFieldNameSelect}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

    $HTMLText
    <div id="${CurrentFieldNameInput}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
    <div id="${CurrentFieldNameInput}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

    <a href="#" id="RemoveValue_$Index" class="RemoveButton ValueRemove"><i class="fa fa-minus-square-o"></i><span class="InvisibleText">Remove value</span></a>
    <div class="SpacingTopMini" ></div>
</div>
EOF
        }
    }

    $DataValues = $Self->BuildSelectionDataGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        PossibleValues     => $PossibleValues,
        Value              => '',
    );

    $HTMLDropdown = $Param{LayoutObject}->BuildSelection(
        Data => $DataValues || {},
        Name => $FieldNameSelect,
        SelectedID  => '',
        Translation => $FieldConfig->{TranslatableValues} || 0,
        Class       => "$FieldClass DFSelectedDocumentsSelect",
        Size        => $Size,
        HTMLQuote   => 1,
    );
    
    $HTMLString = <<"EOF";
                
<div class="Content">
    <fieldset>
        <div class="Field ValueInsert">
            <input type="hidden" name="ValueCounter" value="$Index" id="ValueCounter" class="ValueCounter" />
            $HTMLString
            <div class="ValueTemplate Hidden">
                $HTMLDropdown
                <div id="${FieldNameSelect}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
                <div id="${FieldNameSelect}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

                <input type="text" class="$FieldClass" id="$FieldNameInput" name="$FieldNameInput" value="" />
                <div id="${FieldNameInput}Error" class="TooltipErrorMessage"><p>This field is required.</p></div>
                <div id="${FieldNameInput}ServerError" class="TooltipErrorMessage"><p>Server Error</p></div>

                <a href="#" id="RemoveValue_$Index" class="RemoveButton ValueRemove"><i class="fa fa-minus-square-o"></i><span class="InvisibleText">Remove value</span></a>
                <div class="SpacingTopMini" ></div>
            </div>
            <input type="hidden" name="DeletedValue" value="DeletedString" id="DeletedValue" class="DeletedValue" />
            <div class="Clear"></div>
        </div>
        <div class="Field">
            <a href="#" id="AddValue" class="AddButton"><i class="fa fa-plus-square-o"></i><span class="InvisibleText">Add Value</span></a>
        </div>
    </fieldset>
</div>
EOF
    

    if ( $FieldConfig->{TreeView} ) {
        my $TreeSelectionMessage = $Param{LayoutObject}->{LanguageObject}->Translate("Show Tree Selection");
        $HTMLString
            .= ' <a href="#" title="'
            . $TreeSelectionMessage
            . '" class="ShowTreeSelection"><span>'
            . $TreeSelectionMessage . '</span><i class="fa fa-sitemap"></i></a>';
    }

    if ( $Param{Mandatory} ) {
        my $DivID = $FieldName . 'Error';

        my $FieldRequiredMessage = $Param{LayoutObject}->{LanguageObject}->Translate("This field is required.");

        # for client side validation
        $HTMLString .= <<"EOF";

<div id="$DivID" class="TooltipErrorMessage">
    <p>
        $FieldRequiredMessage
    </p>
</div>
EOF
    }

    if ( $Param{ServerError} ) {

        my $ErrorMessage = $Param{ErrorMessage} || 'This field is required.';
        $ErrorMessage = $Param{LayoutObject}->{LanguageObject}->Translate($ErrorMessage);
        my $DivID = $FieldName . 'ServerError';

        # for server side validation
        $HTMLString .= <<"EOF";

<div id="$DivID" class="TooltipErrorMessage">
    <p>
        $ErrorMessage
    </p>
</div>
EOF
    }

    if ( $Param{AJAXUpdate} ) {

        my $FieldSelector = '.DFSelectedDocumentsSelect';

        my $FieldsToUpdate = '';
        if ( IsArrayRefWithData( $Param{UpdatableFields} ) ) {

            # Remove current field from updatable fields list
            my @FieldsToUpdate = grep { index($_, $FieldNameSelect) eq -1 } @{ $Param{UpdatableFields} };

            # quote all fields, put commas in between them
            $FieldsToUpdate = join( ', ', map {"'$_'"} @FieldsToUpdate );
        }

        # add js to call FormUpdate()
        $Param{LayoutObject}->AddJSOnDocumentComplete( Code => <<"EOF");
\$('$FieldSelector').bind('change', function (Event) {
    Core.AJAX.FormUpdate(\$(this).parents('form'), 'AJAXUpdate', \$(this).attr('name'), [ $FieldsToUpdate ]);
});
EOF
    }

    # add js functions to DropdownAndText dynamic fields
    $Param {LayoutObject}->AddJSOnDocumentComplete( Code => <<"EOF" );
\$('#AddValue').bind('click', function () {
    Core.Agent.Admin.DynamicFieldDropdownAndText.AddValue(
        \$(this).closest('fieldset').find('.ValueInsert')
    );
    return false;
});
\$('.ValueRemove').bind('click', function () {
    Core.Agent.Admin.DynamicFieldDropdownAndText.RemoveValue(\$(this).attr('id'));
    return false;
});
EOF

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        Mandatory => $Param{Mandatory} || '0',
        FieldName => $FieldNameSelect,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldNameSelect = $FieldName . '_Select';
    my $FieldNameInput = $FieldName . '_Input';

    my $Value;
    my $ValueSelect;
    my $ValueInput;
    
    my @Return;

    # check if there is a Template and retrieve the dynamic field value from there
    if ( IsHashRefWithData( $Param{Template} ) && defined $Param{Template}->{$FieldName} ) {
        $Value = $Param{Template}->{$FieldName};
        
        if ( defined $Value ) {
            if ( ref $Value eq 'ARRAY' ) {
                @Return = @{$Value};
            }
            else {
                @Return = ( {$Value => ''} );
            }
        }
    }
    # otherwise get dynamic field value from the web request
    elsif (
        defined $Param{ParamObject}
        && ref $Param{ParamObject} eq 'Kernel::System::Web::Request'
        )
    {
        # cycle through all our dynamic fields, either deleted or not
        my $Index = $Param{ParamObject}->GetParam( Param => "ValueCounter" );
        while ( $Index ) {
            $ValueSelect = $Param{ParamObject}->GetParam( Param => $FieldNameSelect . "_$Index" );
            $ValueInput = $Param{ParamObject}->GetParam( Param => $FieldNameInput . "_$Index" ) || '';
            
            # delete empty values (can happen if the user has selected the "-" entry)
            if ( $ValueSelect ) {
                push @Return, { $ValueSelect => $ValueInput };
            }
            $Index--;
        }
    }

    if ( defined $Param{ReturnTemplateStructure} && $Param{ReturnTemplateStructure} eq 1 ) {
        return {
            $FieldName => \@Return,
        };
    }
    
    return \@Return;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Value = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this Driver but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ValueSelect;
    my $ValueInput;

    my $ServerError;
    my $ErrorMessage;
    
    # get possible values list
    my $PossibleValues = $Param{DynamicFieldConfig}->{Config}->{PossibleValues};

    # overwrite possible values if PossibleValuesFilter
    if ( defined $Param{PossibleValuesFilter} ) {
        $PossibleValues = $Param{PossibleValuesFilter}
    }
    
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            # perform necessary validations
            if ( $Param{Mandatory} && ( $#{$Value} eq -1 ) ) {
                return {
                    ServerError => 1,
                };
            }
            else {
                for my $Item ( @{$Value} ) {
                    $ValueSelect = (keys %{$Item})[0];
                    # validate if value is in possible values list (but let pass empty values)
                    if ( $ValueSelect && !$PossibleValues->{$ValueSelect} ) {
                        $ServerError  = 1;
                        $ErrorMessage = 'The field content is invalid';
                    }
                }
            }
        }
        else {
            if ( $Param{Mandatory} && !$Value ) {
                return {
                    ServerError => 1,
                };
            }
            else {
                if ( ref $Value eq 'HASH' ) {
                    $ValueSelect = (keys %{$Value})[0] || $Value;
                }
                else {
                    $ValueSelect = $Value;
                }
                # validate if value is in possible values list (but let pass empty values)
                if ( $ValueSelect && !$PossibleValues->{$ValueSelect} ) {
                    $ServerError  = 1;
                    $ErrorMessage = 'The field content is invalid';
                }
            }
        }
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # set HTMLOuput as default if not specified
    if ( !defined $Param{HTMLOutput} ) {
        $Param{HTMLOutput} = 1;
    }

    # get raw Value strings from field value
    my $Value = defined $Param{Value} ? $Param{Value} : '';

    my $ValueSelect;
    my $ValueInput;
    my $ReturnValue = '';
    
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            for my $Item ( @{$Value} ) {
                $ValueSelect = (keys %{$Item})[0];
                $ValueInput = (values %{$Item})[0];
                
                # get real value
                if ( $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$ValueSelect} ) {

                    # get readable value
                    $ValueSelect = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$ValueSelect};
                }

                # check is needed to translate values
                if ( $Param{DynamicFieldConfig}->{Config}->{TranslatableValues} ) {

                    # translate value
                    $ValueSelect = $Param{LayoutObject}->{LanguageObject}->Translate($ValueSelect);
                }
                
                # HTMLOuput transformations
                if ( $Param{HTMLOutput} ) {
                    $ValueSelect = $Param{LayoutObject}->Ascii2Html(
                        Text => $ValueSelect,
                        Max  => $Param{ValueMaxChars} || '',
                    );
                    
                    $ValueInput = $Param{LayoutObject}->Ascii2Html(
                        Text => $ValueInput,
                        Max  => $Param{ValueMaxChars} || '',
                    );
                }
                else {
                    if ( $Param{ValueMaxChars} && length($ValueSelect) > $Param{ValueMaxChars} ) {
                        $ValueSelect = substr( $ValueSelect, 0, $Param{ValueMaxChars} ) . '...';
                    }
                    if ( $Param{ValueMaxChars} && length($ValueInput) > $Param{ValueMaxChars} ) {
                        $ValueInput = substr( $ValueInput, 0, $Param{ValueMaxChars} ) . '...';
                    }
                }
                
                if ( !$ValueInput ) {
                    $ReturnValue .= "$ValueSelect;\n";
                }
                else {
                    $ReturnValue .= "$ValueSelect: $ValueInput;\n";
                }
            }
        }
        else {
            if ( ref $Value eq 'HASH' ) {
                $ValueSelect = (keys %{$Value})[0];
                $ValueInput = (values %{$Value})[0];
            }
            else {
                $ValueSelect = $Value || '';
                $ValueInput = '';
            }
            
            # get real value
            if ( $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$ValueSelect} ) {

                # get readable value
                $ValueSelect = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$ValueSelect};
            }

            # check is needed to translate values
            if ( $Param{DynamicFieldConfig}->{Config}->{TranslatableValues} ) {

                # translate value
                $ValueSelect = $Param{LayoutObject}->{LanguageObject}->Translate($ValueSelect);
            }
            
            # HTMLOuput transformations
            if ( $Param{HTMLOutput} ) {
                $ValueSelect = $Param{LayoutObject}->Ascii2Html(
                    Text => $ValueSelect,
                    Max  => $Param{ValueMaxChars} || '',
                );
                
                $ValueInput = $Param{LayoutObject}->Ascii2Html(
                    Text => $ValueInput,
                    Max  => $Param{ValueMaxChars} || '',
                );
            }
            else {
                if ( $Param{ValueMaxChars} && length($ValueSelect) > $Param{ValueMaxChars} ) {
                    $ValueSelect = substr( $ValueSelect, 0, $Param{ValueMaxChars} ) . '...';
                }
                if ( $Param{ValueMaxChars} && length($ValueInput) > $Param{ValueMaxChars} ) {
                    $ValueInput = substr( $ValueInput, 0, $Param{ValueMaxChars} ) . '...';
                }
            }
            
            if ( !$ValueInput ) {
                $ReturnValue .= "$ValueSelect;\n";
            }
            else {
                $ReturnValue .= "$ValueSelect: $ValueInput;\n";
            }
        }
    }

    # set title and execute HTMLOutput transformations
    my $Title = $Param{DynamicFieldConfig}->{Config}->{Name};

    $Title = $Param{LayoutObject}->Ascii2Html(
        Text => $Title,
        Max  => $Param{TitleMaxChars} || '',
    );

    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }
    
    # set field link form config
    my $Link = $Param{DynamicFieldConfig}->{Config}->{Link} || '';

    my $Data = {
        Value => $ReturnValue,
        Title => $Title,
        Link  => $Link,
    };

    return $Data;
}

=notusable
# must be edited before using, currently is a copy-paste of Multiselect.pm

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value;

    my @DefaultValue;

    if ( defined $Param{DefaultValue} ) {
        @DefaultValue = split /;/, $Param{DefaultValue};
    }

    # set the field value
    if (@DefaultValue) {
        $Value = \@DefaultValue;
    }

    # get the field value, this function is always called after the profile is loaded
    my $FieldValues = $Self->SearchFieldValueGet(
        %Param,
    );

    if ( defined $FieldValues ) {
        $Value = $FieldValues;
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldMultiSelect Modernize';

    # set TreeView class
    if ( $FieldConfig->{TreeView} ) {
        $FieldClass .= ' DynamicFieldWithTreeView';
    }

    # set PossibleValues
    my $SelectionData = $FieldConfig->{PossibleValues};

    # get historical values from database
    my $HistoricalValues = $Self->HistoricalValuesGet(%Param);

    # add historic values to current values (if they don't exist anymore)
    if ( IsHashRefWithData($HistoricalValues) ) {
        for my $Key ( sort keys %{$HistoricalValues} ) {
            if ( !$SelectionData->{$Key} ) {
                $SelectionData->{$Key} = $HistoricalValues->{$Key}
            }
        }
    }

    # use PossibleValuesFilter if defined
    $SelectionData = $Param{PossibleValuesFilter} // $SelectionData;

    # check if $SelectionData differs from configured PossibleValues
    # and show values which are not contained as disabled if TreeView => 1
    if ( $FieldConfig->{TreeView} ) {

        if ( keys %{ $FieldConfig->{PossibleValues} } != keys %{$SelectionData} ) {

            my @Values;
            for my $Key ( sort keys %{ $FieldConfig->{PossibleValues} } ) {

                push @Values, {
                    Key      => $Key,
                    Value    => $FieldConfig->{PossibleValues}->{$Key},
                    Disabled => ( defined $SelectionData->{$Key} ) ? 0 : 1,
                };
            }
            $SelectionData = \@Values;
        }
    }

    my $HTMLString = $Param{LayoutObject}->BuildSelection(
        Data         => $SelectionData,
        Name         => $FieldName,
        SelectedID   => $Value,
        Translation  => $FieldConfig->{TranslatableValues} || 0,
        PossibleNone => 0,
        Class        => $FieldClass,
        Multiple     => 1,
        HTMLQuote    => 1,
    );

    if ( $FieldConfig->{TreeView} ) {
        my $TreeSelectionMessage = $Param{LayoutObject}->{LanguageObject}->Translate("Show Tree Selection");
        $HTMLString
            .= ' <a href="#" title="'
            . $TreeSelectionMessage
            . '" class="ShowTreeSelection"><span>'
            . $TreeSelectionMessage . '</span><i class="fa fa-sitemap"></i></a>';
    }

    # call EditLabelRender on the common Driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $Value;

    # get dynamic field value from param object
    if ( defined $Param{ParamObject} ) {
        my @FieldValues = $Param{ParamObject}->GetArray(
            Param => 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name}
        );

        $Value = \@FieldValues;
    }

    # otherwise get the value from the profile
    elsif ( defined $Param{Profile} ) {
        $Value = $Param{Profile}->{ 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} };
    }
    else {
        return;
    }

    if ( defined $Param{ReturnProfileStructure} && $Param{ReturnProfileStructure} eq 1 ) {
        return {
            'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} => $Value,
        };
    }

    return $Value;
}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    my $DisplayValue;

    if ( defined $Value && !$Value ) {
        $DisplayValue = '';
    }

    if ($Value) {
        if ( ref $Value eq 'ARRAY' ) {

            my @DisplayItemList;
            for my $Item ( @{$Value} ) {

                # set the display value
                my $DisplayItem = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Item}
                    || $Item;

                # translate the value
                if (
                    $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                    && defined $Param{LayoutObject}
                    )
                {
                    $DisplayItem = $Param{LayoutObject}->{LanguageObject}->Translate($DisplayItem);
                }

                push @DisplayItemList, $DisplayItem;
            }

            # combine different values into one string
            $DisplayValue = join ' + ', @DisplayItemList;
        }
        else {

            # set the display value
            $DisplayValue = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value};

            # translate the value
            if (
                $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                && defined $Param{LayoutObject}
                )
            {
                $DisplayValue = $Param{LayoutObject}->{LanguageObject}->Translate($DisplayValue);
            }
        }
    }

    # return search parameter structure
    return {
        Parameter => {
            Equals => $Value,
        },
        Display => $DisplayValue,
    };
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # set PossibleValues
    my $Values = $Param{DynamicFieldConfig}->{Config}->{PossibleValues};

    # get historical values from database
    my $HistoricalValues = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text,',
    );

    # add historic values to current values (if they don't exist anymore)
    for my $Key ( sort keys %{$HistoricalValues} ) {
        if ( !$Values->{$Key} ) {
            $Values->{$Key} = $HistoricalValues->{$Key}
        }
    }

    # use PossibleValuesFilter if defined
    $Values = $Param{PossibleValuesFilter} // $Values;

    return {
        Values             => $Values,
        Name               => $Param{DynamicFieldConfig}->{Label},
        Element            => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
        TranslatableValues => $Param{DynamicFieldconfig}->{Config}->{TranslatableValues},
        Block              => 'MultiSelectField',
    };
}

sub StatsSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Operator = 'Equals';
    my $Value    = $Param{Value};

    return {
        $Operator => $Value,
    };
}

=cut

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';

    my $ValueSelect;
    my $ValueInput;
    my @ReturnValue;
    
    if ( defined $Value ) {
        if ( ref $Value eq 'ARRAY' ) {
            for my $Item ( @{$Value} ) {
                $ValueSelect = (keys %{$Item})[0];
                $ValueInput = (values %{$Item})[0];
                
                # cut strings if needed
                if ( $Param{ValueMaxChars} && length($ValueSelect) > $Param{ValueMaxChars} ) {
                    $ValueSelect = substr( $ValueSelect, 0, $Param{ValueMaxChars} ) . '...';
                }
                if ( $Param{ValueMaxChars} && length($ValueInput) > $Param{ValueMaxChars} ) {
                    $ValueInput = substr( $ValueInput, 0, $Param{ValueMaxChars} ) . '...';
                }
                
                push @ReturnValue, { $ValueSelect => $ValueInput };
            }
        }
        elsif (ref $Value eq 'HASH') {
            $ValueSelect = (keys %{$Value})[0];
            $ValueInput = (values %{$Value})[0];
            
            # cut strings if needed
            if ( $Param{ValueMaxChars} && length($ValueSelect) > $Param{ValueMaxChars} ) {
                $ValueSelect = substr( $ValueSelect, 0, $Param{ValueMaxChars} ) . '...';
            }
            if ( $Param{ValueMaxChars} && length($ValueInput) > $Param{ValueMaxChars} ) {
                $ValueInput = substr( $ValueInput, 0, $Param{ValueMaxChars} ) . '...';
            }
            
            push @ReturnValue, { $ValueSelect => $ValueInput };
        }
        else {
            $ValueSelect = $Value || '';
            $ValueInput = '';
            
            # cut strings if needed
            if ( $Param{ValueMaxChars} && length($ValueSelect) > $Param{ValueMaxChars} ) {
                $ValueSelect = substr( $ValueSelect, 0, $Param{ValueMaxChars} ) . '...';
            }
            if ( $Param{ValueMaxChars} && length($ValueInput) > $Param{ValueMaxChars} ) {
                $ValueInput = substr( $ValueInput, 0, $Param{ValueMaxChars} ) . '...';
            }
            
            push @ReturnValue, { $ValueSelect => $ValueInput };
        }
    }

    # set title
    my $Title = $Param{DynamicFieldConfig}->{Config}->{Name};
    if ( $Param{ValueMaxChars} && length($Title) > $Param{ValueMaxChars} ) {
        $Title = substr( $Title, 0, $Param{ValueMaxChars} ) . '...';
    }

    my $Data = {
        Value => \@ReturnValue,
        Title => $Title,
    };

    return $Data;
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'SCALAR';
    my $SearchValueType = 'ARRAY';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
            }
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
            }
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
            }
    }
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # return false if field is not defined
    return 0 if ( !defined $Param{ObjectAttributes}->{$FieldName} );

    # return false if not match
    if ( $Param{ObjectAttributes}->{$FieldName} ne $Param{Value} ) {
        return 0;
    }

    return 1;
}

sub HistoricalValuesGet {
    my ( $Self, %Param ) = @_;

    # get historical values from database
    my $HistoricalValues = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );

    # return the historical values from database
    return $HistoricalValues;
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my $ParamValue = defined $Param{Key} ? $Param{Key} : '';
    my $Value;
    
    if ( ref $ParamValue eq 'ARRAY' ) {
        if ( ref @{$ParamValue}[0] eq 'HASH' ) {
            $Value = (keys %{@{$ParamValue}[0]})[0];
        }
        else {
            $Value = @{$ParamValue}[0];
        }
    }
    elsif ( ref $ParamValue eq 'HASH' ) {
        $Value = (keys %{$ParamValue})[0];
    }
    else {
        $Value = $ParamValue;
    }

    # get real values
    my $PossibleValues = $Param{DynamicFieldConfig}->{Config}->{PossibleValues};

    if ($Value) {

        # check if there is a real value for this key (otherwise keep the key)
        if ( $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value} ) {

            # get readable value
            $Value = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value};

            # check if translation is possible
            if (
                defined $Param{LanguageObject}
                && $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                )
            {

                # translate value
                $Value = $Param{LanguageObject}->Translate($Value);
            }
        }
    }

    return $Value;
}

sub BuildSelectionDataGet {
    my ( $Self, %Param ) = @_;

    my $FieldConfig            = $Param{DynamicFieldConfig}->{Config};
    my $FilteredPossibleValues = $Param{PossibleValues};

    # get the possible values again as it might or might not contain the possible none and it could
    # also be overwritten
    my $ConfigPossibleValues = $Self->PossibleValuesGet(%Param);

    # check if $PossibleValues differs from configured PossibleValues
    # and show values which are not contained as disabled if TreeView => 1
    if ( $FieldConfig->{TreeView} ) {

        if ( keys %{$ConfigPossibleValues} != keys %{$FilteredPossibleValues} ) {

            # define variables to use later in the for loop
            my @Values;
            my $Parents;
            my %DisabledElements;
            my %ProcessedElements;
            my $PosibleNoneSet;

            # loop on all filtered possible values
            for my $Key ( sort keys %{$FilteredPossibleValues} ) {

                # special case for possible none
                if ( !$Key && !$PosibleNoneSet && $FieldConfig->{PossibleNone} ) {

                    # add possible none
                    push @Values, {
                        Key      => $Key,
                        Value    => $ConfigPossibleValues->{$Key} || '-',
                        Selected => defined $Param{Value} || !$Param{Value} ? 1 : 0,
                    };
                }

                # try to split its parents GrandParent::Parent::Son
                my @Elements = split /::/, $Key;

                # reset parents
                $Parents = '';

                # get each element in the hierarchy
                ELEMENT:
                for my $Element (@Elements) {

                    # add its own parents for the complete name
                    my $ElementLongName = $Parents . $Element;

                    # set new parent (before skip already processed)
                    $Parents .= $Element . '::';

                    # skip if already processed
                    next ELEMENT if $ProcessedElements{$ElementLongName};

                    my $Disabled;

                    # check if element exists in the original data or if it is already marked
                    if (
                        !defined $FilteredPossibleValues->{$ElementLongName}
                        && !$DisabledElements{$ElementLongName}
                        )
                    {

                        # mark element as disabled
                        $DisabledElements{$ElementLongName} = 1;

                        # also set the disabled flag for current element to add
                        $Disabled = 1;
                    }

                    # set element as already processed
                    $ProcessedElements{$ElementLongName} = 1;

                    # check if the current element is the selected one
                    my $Selected;
                    if (
                        defined $Param{Value}
                        && $Param{Value}
                        && $ElementLongName eq $Param{Value}
                        )
                    {
                        $Selected = 1;
                    }

                    # add element to the new list of possible values (now including missing parents)
                    push @Values, {
                        Key      => $ElementLongName,
                        Value    => $ConfigPossibleValues->{$ElementLongName} || $ElementLongName,
                        Disabled => $Disabled,
                        Selected => $Selected,
                    };
                }
            }
            $FilteredPossibleValues = \@Values;
        }
    }

    return $FilteredPossibleValues;
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # to store the possible values
    my %PossibleValues;

    # set PossibleNone attribute
    my $FieldPossibleNone;
    if ( defined $Param{OverridePossibleNone} ) {
        $FieldPossibleNone = $Param{OverridePossibleNone};
    }
    else {
        $FieldPossibleNone = $Param{DynamicFieldConfig}->{Config}->{PossibleNone} || 0;
    }

    # set none value if defined on field config
    if ($FieldPossibleNone) {
        %PossibleValues = ( '' => '-' );
    }

    # set all other possible values if defined on field config
    if ( IsHashRefWithData( $Param{DynamicFieldConfig}->{Config}->{PossibleValues} ) ) {
        %PossibleValues = (
            %PossibleValues,
            %{ $Param{DynamicFieldConfig}->{Config}->{PossibleValues} },
        );
    }

    # return the possible values hash as a reference
    return \%PossibleValues;
}

sub ColumnFilterValuesGet {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};

    # set PossibleValues
    my $SelectionData = $FieldConfig->{PossibleValues};

    # get column filter values from database
    my $ColumnFilterValues = $Kernel::OM->Get('Kernel::System::Ticket::ColumnFilter')->DynamicFieldFilterValuesGet(
        TicketIDs => $Param{TicketIDs},
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );

    # get the display value if still exist in dynamic field configuration
    for my $Key ( sort keys %{$ColumnFilterValues} ) {
        if ( $SelectionData->{$Key} ) {
            $ColumnFilterValues->{$Key} = $SelectionData->{$Key}
        }
    }

    if ( $FieldConfig->{TranslatableValues} ) {

        # translate the value
        for my $ValueKey ( sort keys %{$ColumnFilterValues} ) {

            my $OriginalValueName = $ColumnFilterValues->{$ValueKey};
            $ColumnFilterValues->{$ValueKey} = $Param{LayoutObject}->{LanguageObject}->Translate($OriginalValueName);
        }
    }

    return $ColumnFilterValues;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
