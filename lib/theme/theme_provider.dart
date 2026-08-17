import 'package:flutter/material.dart';
import 'dark_mode.dart';
import 'light_mode.dart';

class ThemeProvider extends ChangeNotifier{


  ThemeData themeData = lightMode;

  // ThemeData get themeData => _themeData;



  bool get isDarkMode => themeData == darkMode;

  // set themeData(ThemeData themeData){
  //   _themeData = themeData;
  //   notifyListeners();
  // }


  void toggleTheme(){
    if(themeData == lightMode){
      themeData = darkMode;

    }
    else{
      themeData= lightMode;

    }

    notifyListeners();

  }
}