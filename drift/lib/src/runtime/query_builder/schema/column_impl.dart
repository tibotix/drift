part of '../query_builder.dart';

const VerificationResult _invalidNull = VerificationResult.failure(
    "This column is not nullable and doesn't have a default value. "
    "Null fields thus can't be inserted.");

/// Implementation for a [Column] declared on a table.
class GeneratedColumn<T extends Object> extends Column<T> {
  /// The sql name of this column.
  final String $name; // todo: Remove, replace with `name`

  /// The name of the table that contains this column
  final String tableName;

  /// Whether null values are allowed for this column.
  final bool $nullable;

  /// Default constraints generated by drift.
  final String? _defaultConstraints;

  /// Custom constraints that have been specified for this column.
  ///
  /// Some constraints, like `NOT NULL` or checks for booleans, are generated by
  /// drift by default.
  /// Constraints can also be overridden with [BuildColumn.customConstraint],
  /// in which case the drift constraints will not be applied.
  final String? $customConstraints;

  /// The default expression to be used during inserts when no value has been
  /// specified. Can be null if no default value is set.
  final Expression<T>? defaultValue;

  /// A `CHECK` column constraint present on this column.
  ///
  /// These constraints are evaluated as a boolean during inserts or upserts.
  /// When they evaluate to `false`, the causing statement is rejected.
  ///
  /// Note that this field isn't always set: `CHECK` constraints for tables
  /// defined in `.drift` files are written as raw constraints during build
  /// time.
  /// This field is defined as a lazy function because the check constraint
  /// typically depends on the column itself.
  final Expression<bool> Function()? check;

  /// A function that yields a default column for inserts if no value has been
  /// set. This is different to [defaultValue] since the function is written in
  /// Dart, not SQL. It's a compile-time error to declare columns where both
  /// [defaultValue] and [clientDefault] are non-null.
  ///
  /// See also: [BuildColumn.clientDefault].
  final T? Function()? clientDefault;

  /// Additional checks performed on values before inserts or updates.
  final VerificationResult Function(T?, VerificationMeta)? additionalChecks;

  /// The sql type to use for this column.
  final DriftSqlType<T> type;

  /// If this column is generated (that is, it is a SQL expression of other)
  /// columns, contains information about how to generate this column.
  final GeneratedAs? generatedAs;

  /// Whether a value is required for this column when inserting a new row.
  final bool requiredDuringInsert;

  /// Whether this column has an `AUTOINCREMENT` primary key constraint that was
  /// created by drift.
  bool get hasAutoIncrement =>
      _defaultConstraints?.contains('AUTOINCREMENT') == true;

  @override
  String get name => $name;

  /// Used by generated code.
  GeneratedColumn(
    this.$name,
    this.tableName,
    this.$nullable, {
    this.clientDefault,
    required this.type,
    String? defaultConstraints,
    this.$customConstraints,
    this.defaultValue,
    this.additionalChecks,
    this.requiredDuringInsert = false,
    this.generatedAs,
    this.check,
  }) : _defaultConstraints = defaultConstraints;

  /// Applies a type converter to this column.
  ///
  /// This is mainly used by the generator.
  GeneratedColumnWithTypeConverter<D, T> withConverter<D>(
      TypeConverter<D, T?> converter) {
    return GeneratedColumnWithTypeConverter._(
      converter,
      $name,
      tableName,
      $nullable,
      clientDefault,
      type,
      _defaultConstraints,
      $customConstraints,
      defaultValue,
      additionalChecks,
      requiredDuringInsert,
      generatedAs,
      check,
    );
  }

  /// Writes the definition of this column, as defined
  /// [here](https://www.sqlite.org/syntax/column-def.html), into the given
  /// buffer.
  void writeColumnDefinition(GenerationContext into) {
    final isSerial = into.dialect == SqlDialect.postgres && hasAutoIncrement;

    if (isSerial) {
      into.buffer.write('$escapedName bigserial PRIMARY KEY NOT NULL');
    } else {
      into.buffer.write('$escapedName ${type.sqlTypeName(into)}');
    }

    if ($customConstraints == null) {
      if (!isSerial) {
        into.buffer.write($nullable ? ' NULL' : ' NOT NULL');
      }

      final defaultValue = this.defaultValue;
      if (defaultValue != null) {
        into.buffer.write(' DEFAULT ');

        // we need to write brackets if the default value is not a literal.
        // see https://www.sqlite.org/syntax/column-constraint.html
        final writeBrackets = !defaultValue.isLiteral;

        if (writeBrackets) into.buffer.write('(');
        defaultValue.writeInto(into);
        if (writeBrackets) into.buffer.write(')');
      }

      final generated = generatedAs;
      if (generated != null) {
        into.buffer.write(' GENERATED ALWAYS AS (');
        generated.generatedAs.writeInto(into);
        into.buffer
          ..write(') ')
          ..write(generated.stored ? 'STORED' : 'VIRTUAL');
      }

      final checkExpr = check?.call();
      if (checkExpr != null) {
        into.buffer.write(' CHECK(');
        checkExpr.writeInto(into);
        into.buffer.write(')');
      }

      // these custom constraints refer to builtin constraints from drift
      if (!isSerial && _defaultConstraints != null) {
        into.buffer
          ..write(' ')
          ..write(_defaultConstraints);
      }
    } else if ($customConstraints?.isNotEmpty == true) {
      into.buffer
        ..write(' ')
        ..write($customConstraints);
    }
  }

  @override
  void writeInto(GenerationContext context, {bool ignoreEscape = false}) {
    if (generatedAs != null && context.generatingForView == tableName) {
      generatedAs!.generatedAs.writeInto(context);
    } else {
      if (context.hasMultipleTables) {
        context.buffer
          ..write(context.identifier(tableName))
          ..write('.');
      }
      context.buffer.write(ignoreEscape ? $name : escapedName);
    }
  }

  /// Checks whether the given value fits into this column. The default
  /// implementation only checks for nullability, but subclasses might enforce
  /// additional checks. For instance, a text column might verify that a text
  /// has a certain length.
  VerificationResult isAcceptableValue(T? value, VerificationMeta meta) {
    final nullOk = $nullable;
    if (!nullOk && value == null) {
      return _invalidNull;
    } else {
      return additionalChecks?.call(value, meta) ??
          const VerificationResult.success();
    }
  }

  /// A more general version of [isAcceptableValue] that supports any sql
  /// expression.
  ///
  /// The default implementation will not perform any check if [value] is not
  /// a [Variable].
  VerificationResult isAcceptableOrUnknown(
      Expression value, VerificationMeta meta) {
    if (value is Variable) {
      return isAcceptableValue(value.value as T?, meta);
    } else {
      return const VerificationResult.success();
    }
  }

  @override
  int get hashCode => Object.hash(tableName, $name);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;

    // ignore: test_types_in_equals
    final typedOther = other as GeneratedColumn;
    return typedOther.tableName == tableName && typedOther.$name == $name;
  }

  Variable _evaluateClientDefault() {
    return Variable<T>(clientDefault!());
  }

  /// A value for [additionalChecks] validating allowed text lengths.
  ///
  /// Used by generated code.
  static VerificationResult Function(String?, VerificationMeta) checkTextLength(
      {int? minTextLength, int? maxTextLength}) {
    return (value, meta) {
      if (value == null) return const VerificationResult.success();

      final length = value.length;
      if (minTextLength != null && minTextLength > length) {
        return VerificationResult.failure(
            'Must at least be $minTextLength characters long.');
      }
      if (maxTextLength != null && maxTextLength < length) {
        return VerificationResult.failure(
            'Must at most be $maxTextLength characters long.');
      }

      return const VerificationResult.success();
    };
  }
}

/// A [GeneratedColumn] with a type converter attached to it.
///
/// This provides the [equalsValue] method, which can be used to compare this
/// column against a value mapped through a type converter.
class GeneratedColumnWithTypeConverter<D, S extends Object>
    extends GeneratedColumn<S> {
  /// The type converted used on this column.
  final TypeConverter<D, S?> converter;

  GeneratedColumnWithTypeConverter._(
    this.converter,
    String name,
    String tableName,
    bool nullable,
    S? Function()? clientDefault,
    DriftSqlType<S> type,
    String? defaultConstraints,
    String? customConstraints,
    Expression<S>? defaultValue,
    VerificationResult Function(S?, VerificationMeta)? additionalChecks,
    bool requiredDuringInsert,
    GeneratedAs? generatedAs,
    Expression<bool> Function()? check,
  ) : super(
          name,
          tableName,
          nullable,
          clientDefault: clientDefault,
          type: type,
          defaultConstraints: defaultConstraints,
          $customConstraints: customConstraints,
          defaultValue: defaultValue,
          additionalChecks: additionalChecks,
          requiredDuringInsert: requiredDuringInsert,
          generatedAs: generatedAs,
          check: check,
        );

  S? _mapDartValue(D? dartValue) {
    S? mappedValue;

    if ($nullable) {
      // For nullable columns, the type converter needs to accept null values.
      // ignore: unnecessary_cast, https://github.com/dart-lang/sdk/issues/34150
      mappedValue = (converter as TypeConverter<D?, S?>).toSql(dartValue);
    } else {
      if (dartValue == null) {
        throw ArgumentError(
            "This non-nullable column can't be equal to `null`.", 'dartValue');
      }

      mappedValue = converter.toSql(dartValue);
    }

    if (!$nullable && dartValue == null) {
      throw ArgumentError(
          "This non-nullable column can't be equal to `null`.", 'dartValue');
    }

    return mappedValue;
  }

  /// Compares this column against the mapped [dartValue].
  ///
  /// The value will be mapped using the [converter] applied to this column.
  Expression<bool> equalsValue(D? dartValue) {
    final mappedValue = _mapDartValue(dartValue);
    return mappedValue == null ? this.isNull() : equals(mappedValue);
  }

  /// An expression that is true if `this` resolves to any of the values in
  /// [values].
  ///
  /// The values will be mapped using the [converter] applied to this column.
  Expression<bool> isInValues(Iterable<D> values) {
    return isIn(values.map(_mapDartValue).whereNotNull());
  }

  /// An expression that is true if `this` does not resolve to any of the values
  /// in [values].
  ///
  /// The values will be mapped using the [converter] applied to this column.
  Expression<bool> isNotInValues(Iterable<D> values) {
    return isNotIn(values.map(_mapDartValue).whereNotNull());
  }
}

/// Information filled out by the generator to support generated or virtual
/// columns.
class GeneratedAs {
  /// The expression that this column evaluates to.
  final Expression generatedAs;

  /// Wehter this column is stored in the database, as opposed to being
  /// `VIRTUAL` and evaluated on each read.
  final bool stored;

  /// Creates a [GeneratedAs] clause.
  GeneratedAs(this.generatedAs, this.stored);
}
