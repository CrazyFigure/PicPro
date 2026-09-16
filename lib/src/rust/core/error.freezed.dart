// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PicProError {

 String get field0;
/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProErrorCopyWith<PicProError> get copyWith => _$PicProErrorCopyWithImpl<PicProError>(this as PicProError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProErrorCopyWith<$Res>  {
  factory $PicProErrorCopyWith(PicProError value, $Res Function(PicProError) _then) = _$PicProErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProErrorCopyWithImpl<$Res>
    implements $PicProErrorCopyWith<$Res> {
  _$PicProErrorCopyWithImpl(this._self, this._then);

  final PicProError _self;
  final $Res Function(PicProError) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field0 = null,}) {
  return _then(_self.copyWith(
field0: null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PicProError].
extension PicProErrorPatterns on PicProError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PicProError_UnknownFormat value)?  unknownFormat,TResult Function( PicProError_UnsupportedFormat value)?  unsupportedFormat,TResult Function( PicProError_Decode value)?  decode,TResult Function( PicProError_Encode value)?  encode,TResult Function( PicProError_Svg value)?  svg,TResult Function( PicProError_Io value)?  io,TResult Function( PicProError_TargetUnreachable value)?  targetUnreachable,TResult Function( PicProError_InvalidArgument value)?  invalidArgument,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PicProError_UnknownFormat() when unknownFormat != null:
return unknownFormat(_that);case PicProError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case PicProError_Decode() when decode != null:
return decode(_that);case PicProError_Encode() when encode != null:
return encode(_that);case PicProError_Svg() when svg != null:
return svg(_that);case PicProError_Io() when io != null:
return io(_that);case PicProError_TargetUnreachable() when targetUnreachable != null:
return targetUnreachable(_that);case PicProError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PicProError_UnknownFormat value)  unknownFormat,required TResult Function( PicProError_UnsupportedFormat value)  unsupportedFormat,required TResult Function( PicProError_Decode value)  decode,required TResult Function( PicProError_Encode value)  encode,required TResult Function( PicProError_Svg value)  svg,required TResult Function( PicProError_Io value)  io,required TResult Function( PicProError_TargetUnreachable value)  targetUnreachable,required TResult Function( PicProError_InvalidArgument value)  invalidArgument,}){
final _that = this;
switch (_that) {
case PicProError_UnknownFormat():
return unknownFormat(_that);case PicProError_UnsupportedFormat():
return unsupportedFormat(_that);case PicProError_Decode():
return decode(_that);case PicProError_Encode():
return encode(_that);case PicProError_Svg():
return svg(_that);case PicProError_Io():
return io(_that);case PicProError_TargetUnreachable():
return targetUnreachable(_that);case PicProError_InvalidArgument():
return invalidArgument(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PicProError_UnknownFormat value)?  unknownFormat,TResult? Function( PicProError_UnsupportedFormat value)?  unsupportedFormat,TResult? Function( PicProError_Decode value)?  decode,TResult? Function( PicProError_Encode value)?  encode,TResult? Function( PicProError_Svg value)?  svg,TResult? Function( PicProError_Io value)?  io,TResult? Function( PicProError_TargetUnreachable value)?  targetUnreachable,TResult? Function( PicProError_InvalidArgument value)?  invalidArgument,}){
final _that = this;
switch (_that) {
case PicProError_UnknownFormat() when unknownFormat != null:
return unknownFormat(_that);case PicProError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case PicProError_Decode() when decode != null:
return decode(_that);case PicProError_Encode() when encode != null:
return encode(_that);case PicProError_Svg() when svg != null:
return svg(_that);case PicProError_Io() when io != null:
return io(_that);case PicProError_TargetUnreachable() when targetUnreachable != null:
return targetUnreachable(_that);case PicProError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  unknownFormat,TResult Function( String field0)?  unsupportedFormat,TResult Function( String field0)?  decode,TResult Function( String field0)?  encode,TResult Function( String field0)?  svg,TResult Function( String field0)?  io,TResult Function( String field0)?  targetUnreachable,TResult Function( String field0)?  invalidArgument,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PicProError_UnknownFormat() when unknownFormat != null:
return unknownFormat(_that.field0);case PicProError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that.field0);case PicProError_Decode() when decode != null:
return decode(_that.field0);case PicProError_Encode() when encode != null:
return encode(_that.field0);case PicProError_Svg() when svg != null:
return svg(_that.field0);case PicProError_Io() when io != null:
return io(_that.field0);case PicProError_TargetUnreachable() when targetUnreachable != null:
return targetUnreachable(_that.field0);case PicProError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  unknownFormat,required TResult Function( String field0)  unsupportedFormat,required TResult Function( String field0)  decode,required TResult Function( String field0)  encode,required TResult Function( String field0)  svg,required TResult Function( String field0)  io,required TResult Function( String field0)  targetUnreachable,required TResult Function( String field0)  invalidArgument,}) {final _that = this;
switch (_that) {
case PicProError_UnknownFormat():
return unknownFormat(_that.field0);case PicProError_UnsupportedFormat():
return unsupportedFormat(_that.field0);case PicProError_Decode():
return decode(_that.field0);case PicProError_Encode():
return encode(_that.field0);case PicProError_Svg():
return svg(_that.field0);case PicProError_Io():
return io(_that.field0);case PicProError_TargetUnreachable():
return targetUnreachable(_that.field0);case PicProError_InvalidArgument():
return invalidArgument(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  unknownFormat,TResult? Function( String field0)?  unsupportedFormat,TResult? Function( String field0)?  decode,TResult? Function( String field0)?  encode,TResult? Function( String field0)?  svg,TResult? Function( String field0)?  io,TResult? Function( String field0)?  targetUnreachable,TResult? Function( String field0)?  invalidArgument,}) {final _that = this;
switch (_that) {
case PicProError_UnknownFormat() when unknownFormat != null:
return unknownFormat(_that.field0);case PicProError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that.field0);case PicProError_Decode() when decode != null:
return decode(_that.field0);case PicProError_Encode() when encode != null:
return encode(_that.field0);case PicProError_Svg() when svg != null:
return svg(_that.field0);case PicProError_Io() when io != null:
return io(_that.field0);case PicProError_TargetUnreachable() when targetUnreachable != null:
return targetUnreachable(_that.field0);case PicProError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class PicProError_UnknownFormat extends PicProError {
  const PicProError_UnknownFormat(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_UnknownFormatCopyWith<PicProError_UnknownFormat> get copyWith => _$PicProError_UnknownFormatCopyWithImpl<PicProError_UnknownFormat>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_UnknownFormat&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.unknownFormat(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_UnknownFormatCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_UnknownFormatCopyWith(PicProError_UnknownFormat value, $Res Function(PicProError_UnknownFormat) _then) = _$PicProError_UnknownFormatCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_UnknownFormatCopyWithImpl<$Res>
    implements $PicProError_UnknownFormatCopyWith<$Res> {
  _$PicProError_UnknownFormatCopyWithImpl(this._self, this._then);

  final PicProError_UnknownFormat _self;
  final $Res Function(PicProError_UnknownFormat) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_UnknownFormat(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_UnsupportedFormat extends PicProError {
  const PicProError_UnsupportedFormat(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_UnsupportedFormatCopyWith<PicProError_UnsupportedFormat> get copyWith => _$PicProError_UnsupportedFormatCopyWithImpl<PicProError_UnsupportedFormat>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_UnsupportedFormat&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.unsupportedFormat(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_UnsupportedFormatCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_UnsupportedFormatCopyWith(PicProError_UnsupportedFormat value, $Res Function(PicProError_UnsupportedFormat) _then) = _$PicProError_UnsupportedFormatCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_UnsupportedFormatCopyWithImpl<$Res>
    implements $PicProError_UnsupportedFormatCopyWith<$Res> {
  _$PicProError_UnsupportedFormatCopyWithImpl(this._self, this._then);

  final PicProError_UnsupportedFormat _self;
  final $Res Function(PicProError_UnsupportedFormat) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_UnsupportedFormat(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_Decode extends PicProError {
  const PicProError_Decode(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_DecodeCopyWith<PicProError_Decode> get copyWith => _$PicProError_DecodeCopyWithImpl<PicProError_Decode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_Decode&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.decode(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_DecodeCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_DecodeCopyWith(PicProError_Decode value, $Res Function(PicProError_Decode) _then) = _$PicProError_DecodeCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_DecodeCopyWithImpl<$Res>
    implements $PicProError_DecodeCopyWith<$Res> {
  _$PicProError_DecodeCopyWithImpl(this._self, this._then);

  final PicProError_Decode _self;
  final $Res Function(PicProError_Decode) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_Decode(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_Encode extends PicProError {
  const PicProError_Encode(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_EncodeCopyWith<PicProError_Encode> get copyWith => _$PicProError_EncodeCopyWithImpl<PicProError_Encode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_Encode&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.encode(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_EncodeCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_EncodeCopyWith(PicProError_Encode value, $Res Function(PicProError_Encode) _then) = _$PicProError_EncodeCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_EncodeCopyWithImpl<$Res>
    implements $PicProError_EncodeCopyWith<$Res> {
  _$PicProError_EncodeCopyWithImpl(this._self, this._then);

  final PicProError_Encode _self;
  final $Res Function(PicProError_Encode) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_Encode(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_Svg extends PicProError {
  const PicProError_Svg(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_SvgCopyWith<PicProError_Svg> get copyWith => _$PicProError_SvgCopyWithImpl<PicProError_Svg>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_Svg&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.svg(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_SvgCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_SvgCopyWith(PicProError_Svg value, $Res Function(PicProError_Svg) _then) = _$PicProError_SvgCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_SvgCopyWithImpl<$Res>
    implements $PicProError_SvgCopyWith<$Res> {
  _$PicProError_SvgCopyWithImpl(this._self, this._then);

  final PicProError_Svg _self;
  final $Res Function(PicProError_Svg) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_Svg(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_Io extends PicProError {
  const PicProError_Io(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_IoCopyWith<PicProError_Io> get copyWith => _$PicProError_IoCopyWithImpl<PicProError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_IoCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_IoCopyWith(PicProError_Io value, $Res Function(PicProError_Io) _then) = _$PicProError_IoCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_IoCopyWithImpl<$Res>
    implements $PicProError_IoCopyWith<$Res> {
  _$PicProError_IoCopyWithImpl(this._self, this._then);

  final PicProError_Io _self;
  final $Res Function(PicProError_Io) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_TargetUnreachable extends PicProError {
  const PicProError_TargetUnreachable(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_TargetUnreachableCopyWith<PicProError_TargetUnreachable> get copyWith => _$PicProError_TargetUnreachableCopyWithImpl<PicProError_TargetUnreachable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_TargetUnreachable&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.targetUnreachable(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_TargetUnreachableCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_TargetUnreachableCopyWith(PicProError_TargetUnreachable value, $Res Function(PicProError_TargetUnreachable) _then) = _$PicProError_TargetUnreachableCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_TargetUnreachableCopyWithImpl<$Res>
    implements $PicProError_TargetUnreachableCopyWith<$Res> {
  _$PicProError_TargetUnreachableCopyWithImpl(this._self, this._then);

  final PicProError_TargetUnreachable _self;
  final $Res Function(PicProError_TargetUnreachable) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_TargetUnreachable(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PicProError_InvalidArgument extends PicProError {
  const PicProError_InvalidArgument(this.field0): super._();
  

@override final  String field0;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PicProError_InvalidArgumentCopyWith<PicProError_InvalidArgument> get copyWith => _$PicProError_InvalidArgumentCopyWithImpl<PicProError_InvalidArgument>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PicProError_InvalidArgument&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PicProError.invalidArgument(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PicProError_InvalidArgumentCopyWith<$Res> implements $PicProErrorCopyWith<$Res> {
  factory $PicProError_InvalidArgumentCopyWith(PicProError_InvalidArgument value, $Res Function(PicProError_InvalidArgument) _then) = _$PicProError_InvalidArgumentCopyWithImpl;
@override @useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PicProError_InvalidArgumentCopyWithImpl<$Res>
    implements $PicProError_InvalidArgumentCopyWith<$Res> {
  _$PicProError_InvalidArgumentCopyWithImpl(this._self, this._then);

  final PicProError_InvalidArgument _self;
  final $Res Function(PicProError_InvalidArgument) _then;

/// Create a copy of PicProError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PicProError_InvalidArgument(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
